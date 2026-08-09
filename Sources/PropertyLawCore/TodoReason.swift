/// Human-readable `.todo` diagnostics — split out of `DerivationStrategy`
/// so that file stays focused on the strategy machinery. Surfaced as the
/// macro's warning alongside the deliberate compile error (PRD §5.7).
extension DerivationStrategist {

    /// Explanation for why no strategy applied, by type kind.
    static func todoReason(
        for shape: TypeShape,
        emissionSite: EmissionSite = .separateFile,
        resolve: CustomTypeResolver = { _ in nil }
    ) -> String {
        // Ahead of the kind switch, because `kind` is not knowledge here.
        //
        // **Measured 2026-08-08 on swift-syntax + swift-argument-parser: 435 of
        // the 449 types in the "no visible stored properties" bucket had no
        // declaration in the scanned target at all.** They were reported as
        // structs whose body lacked stored properties — a sentence about a
        // declaration nobody had read. An enum lands here too: with no primary
        // declaration the scanner cannot know the kind, `TypeShape.kind` falls
        // back to `.struct`, and the enum is described as a struct.
        if !shape.hasPrimaryDeclaration {
            return "Cannot derive a generator for `\(shape.name)`: this target "
                + "only extends the type; its declaration was not scanned, so "
                + "no members, initializers or cases are visible and even its "
                + "kind is unknown. Types declared in another module need a "
                + "`static func gen() -> Generator<\(shape.name), some "
                + "SendableSequenceType>` supplied here."
        }
        switch shape.kind {
        case .enum:
            return enumTodoReason(for: shape, resolve: resolve)
        case .struct:
            return structTodoReason(for: shape, emissionSite: emissionSite)
        case .class, .actor:
            return "Cannot derive a generator for `\(shape.name)`: memberwise "
                + "derivation supports structs only (class/actor reference "
                + "semantics complicate the synthesized-init contract). "
                + "Provide `static func gen() -> Generator<\(shape.name), "
                + "some SendableSequenceType>`."
        }
    }

    /// **Every enum that failed to derive used to be reported the same way**:
    /// *"not `CaseIterable` and no recognized stdlib raw type … or add
    /// `: CaseIterable`."* Tier 4 case enumeration made that obsolete and the
    /// message was never revisited, so it survived as a catch-all over four
    /// unrelated causes — and for the commonest one the advice is **impossible
    /// to follow**: an enum with associated values cannot conform to
    /// `CaseIterable` at all. In the road-test corpus, 264 of the case
    /// declarations across 113 enums carry associated values.
    ///
    /// The same defect shape as the two access-level diagnostics one tier up: a
    /// reason string that names the first thing anyone thought of rather than
    /// the thing that actually happened.
    private static func enumTodoReason(
        for shape: TypeShape,
        resolve: CustomTypeResolver
    ) -> String {
        let prefix = "Cannot derive a generator for `\(shape.name)`: "
        let gen = " Provide `static func gen() -> Generator<\(shape.name), "
            + "some SendableSequenceType>`."

        if shape.enumCases.isEmpty {
            // `kind` is only set to `.enum` from a primary declaration, so
            // reaching here with no cases means the body really was empty —
            // a namespace enum, which is *uninhabited*. No generator exists
            // because no value exists, and `: CaseIterable` would not help:
            // `allCases` would be empty and the generator would never yield.
            return prefix + "the enum declares no cases, so it has no values to "
                + "generate. A caseless enum is uninhabited; property laws over "
                + "it are vacuous. If this is a namespace rather than a value "
                + "type, it needs no conformance and no generator."
        }
        if let wide = shape.enumCases.first(where: {
            $0.associatedValues.count > memberwiseArityLimit
        }) {
            return prefix + "case `\(wide.name)` has "
                + "\(wide.associatedValues.count) associated values; case "
                + "enumeration supports up to \(memberwiseArityLimit)." + gen
        }
        for enumCase in shape.enumCases {
            for value in enumCase.associatedValues
            where composedGenerator(forTypeName: value.typeName, resolve: resolve) == nil {
                return prefix + "case `\(enumCase.name)` has an associated value "
                    + "of type `\(value.typeName)`, which resolves to no generator."
                    + gen
            }
        }
        return prefix + "the enum's cases could not be enumerated, and it is "
            + "neither `CaseIterable` nor backed by a recognized stdlib raw "
            + "type." + gen
    }

    /// Diagnostic for struct cases that fell through memberwise derivation
    /// — names the specific reason so the user knows whether to add a
    /// `gen()` or restructure the type.
    private static func structTodoReason(
        for shape: TypeShape,
        emissionSite: EmissionSite
    ) -> String {
        let prefix = "Cannot derive a generator for `\(shape.name)`: "
        let suffix = " Provide `static func gen() -> Generator<\(shape.name), "
            + "some SendableSequenceType>`."
        if shape.storedMembers.isEmpty {
            return prefix + "the type's primary declaration has no stored "
                + "properties visible to the macro." + suffix
        }
        if shape.hasUserInit {
            return userInitTodoReason(for: shape, emissionSite: emissionSite)
        }
        if shape.storedMembers.count > memberwiseMemberLimit {
            return prefix + "the type has \(shape.storedMembers.count) stored "
                + "properties; memberwise derivation supports up to "
                + "\(memberwiseMemberLimit) (nested `zip` composition, "
                + "\(memberwiseArityLimit) groups of \(memberwiseArityLimit))."
                + suffix
        }
        if let blocked = shape.storedMembers
            .firstBlockingMemberwiseDerivation(from: emissionSite) {
            return memberAccessTodoReason(for: shape, blocked: blocked, emissionSite: emissionSite)
        }
        if let unknown = shape.storedMembers.first(where: {
            RawType(typeName: $0.typeName) == nil
                && memberGenerator(forTypeName: $0.typeName) == nil
        }) {
            return prefix + "stored property `\(unknown.name): "
                + "\(unknown.typeName)` has no recognized stdlib raw type "
                + "(memberwise derivation supports Int/String/Bool/Double/"
                + "Float, the fixed-width integer family, Character, and Date, "
                + "plus optionals, arrays, sets, and dictionaries of those)." + suffix
        }
        return prefix + "memberwise derivation didn't apply." + suffix
    }

    /// The user-`init` branch. Split out of `structTodoReason` when the
    /// access arms took it past the function-body-length lint.
    private static func userInitTodoReason(
        for shape: TypeShape,
        emissionSite: EmissionSite
    ) -> String {
        let prefix = "Cannot derive a generator for `\(shape.name)`: "
        let gen = " Provide `static func gen() -> Generator<\(shape.name), "
            + "some SendableSequenceType>`."
        if shape.initializers.isEmpty {
            return prefix + "the type declares a user `init(...)` in its "
                + "primary body, which suppresses Swift's synthesized "
                + "memberwise initializer." + gen
        }
        // Ahead of the catch-all: telling a user their parameter types don't
        // resolve, when the real problem is that the initializer is `private`,
        // sends them to inspect types that are fine.
        if shape.initializers.allSatisfy({ !$0.accessLevel.isCallable(from: emissionSite) }) {
            let levels = Set(shape.initializers.map(\.accessLevel.rawValue)).sorted()
            return prefix + "every initializer the type declares is "
                + "\(levels.joined(separator: " / ")), so the generated test cannot "
                + "call one. Widen an initializer's access level, or provide "
                + "`static func gen() -> Generator<\(shape.name), "
                + "some SendableSequenceType>`."
        }
        return prefix + "the type's user `init(...)` declarations don't "
            + "support derivation — no non-failable, non-throwing "
            + "initializer (with 1–\(memberwiseMemberLimit) parameters) has "
            + "all parameter types resolve to a recognized generator." + gen
    }

    /// The restricted-stored-property branch, split out for the same reason.
    private static func memberAccessTodoReason(
        for shape: TypeShape,
        blocked: StoredMember,
        emissionSite: EmissionSite
    ) -> String {
        let initAccess = shape.storedMembers.synthesizedMemberwiseInitAccess
        return "Cannot derive a generator for `\(shape.name)`: stored property "
            + "`\(blocked.name)` is declared `\(blocked.accessLevel.rawValue)`, so "
            + "Swift synthesizes a `\(initAccess.rawValue)` memberwise initializer "
            + "\(reachClause(initAccess, emissionSite)). Widen the property's access "
            + "level, or provide `static func gen() -> Generator<\(shape.name), "
            + "some SendableSequenceType>`."
    }

    /// Names *who* can't reach the synthesized initializer, which differs by
    /// site — a `fileprivate` init is fine for the peer macro and out of reach
    /// for the discovery plugin's separate test file. Stating it this way keeps
    /// the diagnostic actionable in both consumers rather than generically true.
    private static func reachClause(
        _ initAccess: AccessLevel,
        _ site: EmissionSite
    ) -> String {
        switch initAccess {
        case .private:
            return "no caller outside the type's own body can reach — "
                + "not even a peer declaration in the same file"
        case .fileprivate:
            return site == .sameFile
                ? "cannot be reached"
                : "the generated test, being in another file, cannot reach"
        case .internal, .package, .public, .open:
            return "cannot be reached"
        }
    }
}
