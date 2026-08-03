import SwiftSyntax

/// Rewrites the canonical Swift collection constructor into a type the generator resolver
/// already understands.
///
/// `init<S: Sequence>(_ items: S) where S.Element == Element` is how essentially every Swift
/// collection is built — `Array`, `Set`, `Deque`, `OrderedSet`, `TreeSet`, `BitSet`,
/// `PersistentSet`. The parameter's declared type is the generic parameter `S`, which
/// resolves to no generator, so Tier 6 walked straight past it. Measured on
/// swift-collections: every public collection type reported *"no non-failable, non-throwing
/// initializer has all parameter types resolve to a recognized generator"* while declaring
/// exactly this initializer.
///
/// **The rewrite is a fact, not a heuristic.** An initializer taking `some Sequence` whose
/// `Element` is `X` accepts `[X]`, so recording the parameter as `[X]` describes what the
/// initializer will actually take. Everything downstream then works unchanged:
/// `CompositeMemberParser` already handles `[T]` sugar and emits
/// `<element>.array(of: 0...8)`, which composes to
/// `Gen<Int>.int(…).array(of: 0...8).map { Deque($0) }` — the same expression
/// `PropertyLawCollections.smallIntDeque` writes by hand. No new strategy tier, no emitter
/// change.
///
/// **What it deliberately does not do.** The element type is recorded as written. For a
/// generic carrier the `where` clause names the carrier's own parameter (`S.Element ==
/// Element`), which resolves to nothing here, so the initializer stays undeliverable and the
/// carrier still reports `.todo`. Substituting a concrete type needs the *enclosing*
/// declaration's generic parameters, which a member block does not carry — a caller that has
/// them (SwiftInferProperties' scanner does) can substitute before calling. Being wrong about
/// the element type would emit code that does not compile, so the conservative half stays
/// here.
public enum SequenceInitializerNormalizer {

    /// The parameter type to record, given one initializer's syntax and the declared type of
    /// one of its parameters. Returns the type unchanged unless this is the sequence shape.
    ///
    /// Requires ALL of: exactly one generic parameter on the initializer, constrained to
    /// `Sequence` (or `Collection`, which refines it); the parameter's type is that generic
    /// parameter, modulo ownership sigils; and a `where` clause pinning its `Element`. Every
    /// clause is load-bearing — a `Sequence`-constrained parameter with no `Element`
    /// requirement could be a sequence of anything, and guessing would emit a call that does
    /// not typecheck.
    public static func normalizedTypeName(
        declared typeName: String,
        initializer: InitializerDeclSyntax
    ) -> String {
        // `some Sequence<Element>` — the primary-associated-type spelling, which states the
        // element inline and needs no generic or where clause. **Measured on
        // swift-collections: 159 occurrences against 8 of the `init<S: Sequence>` form.**
        // The first version of this file matched only the rare spelling and therefore did
        // nothing on the corpus it was written for.
        if let element = opaqueSequenceElement(strippingOwnership(typeName)) {
            return "[\(element)]"
        }
        guard let generics = initializer.genericParameterClause,
              generics.parameters.count == 1,
              let generic = generics.parameters.first else { return typeName }

        let constraint = generic.inheritedType?.trimmedDescription
        guard constraint == "Sequence" || constraint == "Collection" else { return typeName }

        let bare = strippingOwnership(typeName)
        guard bare == generic.name.text else { return typeName }

        guard let element = elementRequirement(
            for: generic.name.text, in: initializer.genericWhereClause
        ) else { return typeName }

        return "[\(element)]"
    }

    /// The `X` in `some Sequence<X>` / `some Collection<X>`, or `nil`.
    ///
    /// A bare `some Sequence` with no primary associated type is declined for the same reason
    /// a missing `where` clause is: it is a sequence of anything, and guessing the element
    /// emits a call that does not typecheck.
    static func opaqueSequenceElement(_ typeName: String) -> String? {
        for keyword in ["some Sequence<", "some Collection<"] where typeName.hasPrefix(keyword) {
            guard typeName.hasSuffix(">") else { continue }
            let element = String(typeName.dropFirst(keyword.count).dropLast())
            return element.isEmpty ? nil : element
        }
        return nil
    }

    /// The right-hand side of `S.Element == X`, or `nil` when the clause does not pin it.
    static func elementRequirement(
        for genericName: String,
        in whereClause: GenericWhereClauseSyntax?
    ) -> String? {
        guard let whereClause else { return nil }
        for requirement in whereClause.requirements {
            guard let sameType = requirement.requirement.as(SameTypeRequirementSyntax.self) else {
                continue
            }
            let left = sameType.leftType.trimmedDescription
            guard left == "\(genericName).Element" else { continue }
            return sameType.rightType.trimmedDescription
        }
        return nil
    }

    /// Ownership sigils are calling-convention detail the generator never sees.
    /// swift-collections writes `__owned S`, which would otherwise fail the name comparison.
    static func strippingOwnership(_ raw: String) -> String {
        var text = Substring(raw)
        let sigils = ["__owned ", "__shared ", "consuming ", "borrowing ", "sending "]
        stripping: while true {
            for sigil in sigils where text.hasPrefix(sigil) {
                text = text.dropFirst(sigil.count)
                continue stripping
            }
            break
        }
        return String(text.drop(while: { $0 == " " }))
    }
}
