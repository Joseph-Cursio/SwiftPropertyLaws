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
            return structTodoReason(for: shape, emissionSite: emissionSite, resolve: resolve)
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
                    + "of type `\(value.typeName)`, which resolves to no generator"
                    + leafClause(for: value.typeName, resolve: resolve) + "." + gen
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
        emissionSite: EmissionSite,
        resolve: CustomTypeResolver
    ) -> String {
        let prefix = "Cannot derive a generator for `\(shape.name)`: "
        let suffix = " Provide `static func gen() -> Generator<\(shape.name), "
            + "some SendableSequenceType>`."
        // Reached only when `statelessStrategy` declined, which for a declared
        // memberless struct means its `init`s rule out `T()`. The phrase "no
        // stored properties" is the discovery tool's category needle.
        if shape.storedMembers.isEmpty {
            return prefix + "the type has no stored properties, so `\(shape.name)()` "
                + "would be its only value — but its primary declaration declares "
                + "a user `init(...)` and none is a callable, non-failable, "
                + "non-throwing `init()`, so there is no `\(shape.name)()` to call."
                + suffix
        }
        if shape.hasUserInit {
            return userInitTodoReason(for: shape, emissionSite: emissionSite, resolve: resolve)
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
        // **Consults `resolve`, the same rule `enumTodoReason` follows.** This
        // arm used to test members against the stdlib table alone, so under the
        // discovery plugin's whole-module resolver it named the first *custom*
        // member — which may well have resolved — rather than the one that did
        // not, and called it a missing "stdlib raw type" either way. A reader
        // then inspected a type that was fine.
        if let unresolved = shape.storedMembers.first(where: {
            RawType(typeName: $0.typeName) == nil
                && composedGenerator(forTypeName: $0.typeName, resolve: resolve) == nil
        }) {
            // Name the leaf, not the composite: `[String: [Widget]]` is fine
            // around a `Widget` that is not.
            let leaf = firstUnresolvedLeaf(inTypeName: unresolved.typeName, resolve: resolve)
                ?? unresolved.typeName
            let within = leaf == unresolved.typeName ? "" : ", inside `\(unresolved.typeName)`,"
            return prefix + "stored property `\(unresolved.name): "
                + "\(unresolved.typeName)` resolves to no generator — "
                + "`\(leaf)`\(within) is not a recognized stdlib type "
                + "(memberwise derivation supports Int/String/Bool/Double/"
                + "Float, the fixed-width integer family, Character, and Date, "
                + "plus optionals, arrays, sets, and dictionaries of those), "
                + "and no generator could be derived for it from the types in "
                + "scope." + suffix
        }
        return prefix + "memberwise derivation didn't apply." + suffix
    }

    /// The user-`init` branch. Split out of `structTodoReason` when the
    /// access arms took it past the function-body-length lint.
    private static func userInitTodoReason(
        for shape: TypeShape,
        emissionSite: EmissionSite,
        resolve: CustomTypeResolver
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
        // The initializers `initializerBasedStrategy` actually tried, in the
        // order it tried them — so the parameter named is the one that stopped
        // the first candidate, not merely some parameter that fails in isolation.
        let candidates = shape.initializers.filter {
            !isDeclined($0, in: shape, from: emissionSite)
        }
        for initializer in candidates {
            if let unresolved = initializer.parameters.first(where: {
                composedGenerator(forTypeName: $0.typeName, resolve: resolve) == nil
            }) {
                return prefix + "no user `init(...)` derives — "
                    + "`\(signature(of: initializer))` takes "
                    + "`\(unresolved.label ?? "_"): \(unresolved.typeName)`, which "
                    + "resolves to no generator"
                    + leafClause(for: unresolved.typeName, resolve: resolve) + "." + gen
            }
        }
        // Every initializer was declined before its parameters were consulted,
        // so a sentence about parameter types would point at types that are fine.
        return prefix + "the type's user `init(...)` declarations don't "
            + "support derivation — each is failable, throwing, "
            + "access-restricted, parameterless, over "
            + "\(memberwiseMemberLimit) parameters, or unsafe to call with "
            + "independently drawn arguments (a capacity hint, a "
            + "private-storage label, or a stated precondition)." + gen
    }

    /// ` because `Widget` does not` when a composite failed on an inner leaf;
    /// empty when the spelling is itself the leaf, so a bare type reads as before.
    private static func leafClause(for typeName: String, resolve: CustomTypeResolver) -> String {
        guard let leaf = firstUnresolvedLeaf(inTypeName: typeName, resolve: resolve),
              leaf != typeName else { return "" }
        return " because `\(leaf)` does not"
    }

    /// `init(registry:_:)` — the spelling a reader searches the source for.
    private static func signature(of initializer: InitializerSignature) -> String {
        "init(" + initializer.parameters.map { ($0.label ?? "_") + ":" }.joined() + ")"
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
