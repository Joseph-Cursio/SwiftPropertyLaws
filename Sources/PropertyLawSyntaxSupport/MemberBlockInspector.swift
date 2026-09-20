import PropertyLawCore
import SwiftSyntax

/// Pure SwiftSyntax helpers that walk a `MemberBlockSyntax` to extract the
/// syntactic info `DerivationStrategist` and `KnownProtocol` consumers need.
///
/// Lives in its own leaf target (depending only on `PropertyLawCore` +
/// `SwiftSyntax`, not the macro/`SwiftCompilerPlugin` machinery) so both the
/// macro impl (`PropertyLawMacroImpl`) and the discovery plugin
/// (`PropertyLawDiscoveryTool`) can share one copy without the plugin taking
/// a compile-time dependency on the macro target. This preserves PRD §9
/// Decision 4's macro/plugin separation while removing the previously
/// duplicated `MemberBlockInspector` / `PluginMemberInspector` twins.
public enum MemberBlockInspector {

    /// Stored properties declared in `memberBlock`, in source order.
    /// Returns only `let`/`var` declarations with explicit type
    /// annotations; computed properties (`{ get/set }` or a bare getter body)
    /// are skipped. Multi-binding lines like `let x: Int, y: Int` produce one
    /// entry per binding, and a tuple pattern `let (x, y): (Int, Int)` one
    /// entry per element.
    ///
    /// **An observed property is stored, and is recorded.** `var count: Int
    /// { didSet { … } }` carries an accessor block, and an earlier reading
    /// skipped every binding that did — so the property vanished from the
    /// shape while the synthesized memberwise initializer still took it. The
    /// memberwise strategy then emitted `Observed()` for a type whose only
    /// initializer is `Observed(count:)`, and an empty member list reads as a
    /// stateless type, which a no-argument generator would construct the same
    /// broken way. Checked with `swiftc -typecheck` on 2026-09-16: *"missing
    /// argument for parameter 'count' in call"*. Tuple patterns were dropped
    /// the same way and fail the same way.
    public static func storedMembers(in memberBlock: MemberBlockSyntax) -> [StoredMember] {
        var result: [StoredMember] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !isStaticOrClass(varDecl) else { continue }
            for binding in varDecl.bindings {
                if let accessorBlock = binding.accessorBlock, !isObserversOnly(accessorBlock) {
                    continue
                }
                guard let typeAnnotation = binding.typeAnnotation else { continue }
                for (name, typeName) in namedTypes(of: binding.pattern, annotated: typeAnnotation.type) {
                    result.append(StoredMember(
                        name: name,
                        typeName: typeName,
                        accessLevel: accessLevel(of: varDecl)
                    ))
                }
            }
        }
        return result
    }

    /// `willSet` / `didSet` only — the accessor block of a stored property.
    /// A bare getter body, or any `get` / `set` / `_read` / `_modify` accessor,
    /// makes the property computed.
    static func isObserversOnly(_ accessorBlock: AccessorBlockSyntax) -> Bool {
        guard case .accessors(let accessors) = accessorBlock.accessors else { return false }
        return accessors.allSatisfy { accessor in
            accessor.accessorSpecifier.tokenKind == .keyword(.willSet)
                || accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
        }
    }

    /// The `(name, type)` pairs a binding pattern declares against its type
    /// annotation. A tuple pattern pairs element-wise with a tuple type of the
    /// same arity, recursively; a part that doesn't line up (a wildcard, a
    /// mismatched arity) contributes nothing rather than a guessed pairing.
    private static func namedTypes(
        of pattern: PatternSyntax,
        annotated type: TypeSyntax
    ) -> [(name: String, typeName: String)] {
        if let identifier = pattern.as(IdentifierPatternSyntax.self) {
            return [(identifier.identifier.text, type.trimmedDescription)]
        }
        guard let tuplePattern = pattern.as(TuplePatternSyntax.self),
              let tupleType = type.as(TupleTypeSyntax.self),
              tuplePattern.elements.count == tupleType.elements.count else { return [] }
        return zip(tuplePattern.elements, tupleType.elements).flatMap { patternElement, typeElement in
            namedTypes(of: patternElement.pattern, annotated: typeElement.type)
        }
    }

    /// True when the type's primary declaration body contains any `init`.
    /// Swift suppresses the synthesized memberwise initializer in that
    /// case — memberwise-Arbitrary derivation must fall through.
    public static func hasUserInit(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members
        where member.decl.as(InitializerDeclSyntax.self) != nil {
            return true
        }
        return false
    }

    /// User-declared initializers in `memberBlock`, in source order, for the
    /// Tier 6 `initializerBased` strategy. Async initializers are skipped
    /// entirely (they can't be lifted through a synchronous generator `map`);
    /// failable (`init?`) and throwing inits are captured with flags so the
    /// strategist can decline them while still reporting an accurate `.todo`
    /// reason. Initializers with a variadic parameter are skipped (their call
    /// shape doesn't compose into a fixed-arity `zip`).
    public static func initializers(in memberBlock: MemberBlockSyntax) -> [InitializerSignature] {
        var result: [InitializerSignature] = []
        for member in memberBlock.members {
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { continue }
            let effects = initDecl.signature.effectSpecifiers
            if effects?.asyncSpecifier != nil { continue }

            var parameters: [InitializerParameter] = []
            var hasVariadic = false
            for param in initDecl.signature.parameterClause.parameters {
                if param.ellipsis != nil { hasVariadic = true; break }
                let firstName = param.firstName.text
                let label = firstName == "_" ? nil : firstName
                parameters.append(InitializerParameter(
                    label: label,
                    // `init<S: Sequence>(_ items: S) where S.Element == X` is recorded as
                    // taking `[X]`, which is what it accepts. See
                    // `SequenceInitializerNormalizer` — without this the canonical Swift
                    // collection constructor resolves to no generator and every collection
                    // type reports `.todo`.
                    typeName: SequenceInitializerNormalizer.normalizedTypeName(
                        declared: param.type.trimmedDescription, initializer: initDecl
                    )
                ))
            }
            if hasVariadic { continue }

            result.append(InitializerSignature(
                parameters: parameters,
                isFailable: initDecl.optionalMark != nil,
                isThrowing: effects?.throwsClause != nil,
                assertsPrecondition: InitializerPreconditionDetector
                    .statesPrecondition(initDecl),
                delegatesToSelf: InitializerPreconditionDetector.delegatesToSelf(initDecl),
                accessLevel: accessLevel(of: initDecl.modifiers)
            ))
        }
        return result
    }

    /// Enum cases declared in `memberBlock`, in source order, for the Tier 4
    /// `enumCases` strategy. One `case a, b` declaration yields one entry per
    /// element. Each associated value's label is its first name (the
    /// construction label), or `nil` when unlabeled (`_` or absent).
    public static func enumCases(in memberBlock: MemberBlockSyntax) -> [EnumCase] {
        var result: [EnumCase] = []
        for member in memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements {
                var associatedValues: [InitializerParameter] = []
                if let parameters = element.parameterClause?.parameters {
                    for parameter in parameters {
                        let first = parameter.firstName?.text
                        let label = (first == nil || first == "_") ? nil : first
                        associatedValues.append(InitializerParameter(
                            label: label,
                            typeName: parameter.type.trimmedDescription
                        ))
                    }
                }
                result.append(EnumCase(name: element.name.text, associatedValues: associatedValues))
            }
        }
        return result
    }

    /// Declared access level of a stored property, or `.implicit` when no
    /// access modifier is written.
    ///
    /// **Detail-carrying modifiers are skipped, and that is the whole
    /// subtlety.** `private(set) var b: Int` writes `private` in the syntax but
    /// restricts only the setter — the synthesized memberwise initializer
    /// follows the *getter*, so `Type(a:b:)` stays `internal` and compiles from
    /// another file. Verified against the compiler on 2026-08-08: a two-file
    /// `swiftc -typecheck` accepts the cross-file call for `private(set)` and
    /// rejects it for `fileprivate`. Reading the modifier name alone would
    /// decline a derivable type on a spelling.
    private static func accessLevel(of decl: VariableDeclSyntax) -> AccessLevel {
        accessLevel(of: decl.modifiers)
    }

    /// Shared by the stored-property reader, the initializer reader, and
    /// `ModuleScanner`'s type-declaration reader, so a `private` type, a
    /// `private` init and a `private` member are all recognised by one rule —
    /// including the `private(set)` exclusion, which each of them would
    /// otherwise have to remember separately.
    public static func accessLevel(of modifiers: DeclModifierListSyntax) -> AccessLevel {
        for modifier in modifiers where modifier.detail == nil {
            if let level = AccessLevel(modifierName: modifier.name.text) {
                return level
            }
        }
        return .implicit
    }

    static func isStaticOrClass(_ decl: VariableDeclSyntax) -> Bool {
        decl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
    }
}
