import Testing
@testable import PropertyLawCore

/// The same defect as the memberwise access rule, one tier down: Tier 6 lifts
/// through a *written* initializer, and a `private init` cannot be called from
/// a generated test any more than a `private` synthesized one can.
///
/// Measured 2026-08-08 on a fixture reduced from the shape the discovery tool
/// hit: `public struct PrivateInit { private init(a:b:) }` derived
/// `zip(Gen<Int>.int(), Gen<Int>.int()).map { PrivateInit(a: $0.0, b: $0.1) }`
/// — a call the emitted file cannot make. `takesPrivateStorage` did not catch
/// it (the labels are `a` and `b`, neither `_`-prefixed nor a measurement) and
/// nothing else looked at access.
///
/// The rule declines the *initializer*, not the type, which matters: the
/// strategist iterates `shape.initializers`, so a type with one restricted and
/// one reachable initializer still derives.
struct InitializerAccessDerivationTests {

    private func shape(_ initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: "Subject",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "a", typeName: "Int")],
            hasUserInit: true,
            initializers: initializers
        )
    }

    private func initializer(
        _ labels: [String],
        _ access: AccessLevel = .implicit
    ) -> InitializerSignature {
        InitializerSignature(
            parameters: labels.map { InitializerParameter(label: $0, typeName: "Int") },
            accessLevel: access
        )
    }

    @Test("a private initializer does not derive, at either site")
    func privateInitializerDeclines() {
        let subject = shape([initializer(["a", "b"], .private)])
        for site in EmissionSite.allCases {
            guard case .todo = DerivationStrategist.strategy(
                for: subject, emissionSite: site
            ) else {
                Issue.record("expected .todo at \(site)")
                return
            }
        }
    }

    @Test("a fileprivate initializer derives in-file and not out of it")
    func fileprivateInitializerIsSiteDependent() {
        let subject = shape([initializer(["a", "b"], .fileprivate)])
        guard case .initializerBased = DerivationStrategist.strategy(
            for: subject, emissionSite: .sameFile
        ) else {
            Issue.record("expected derivation for same-file emission")
            return
        }
        guard case .todo = DerivationStrategist.strategy(
            for: subject, emissionSite: .separateFile
        ) else {
            Issue.record("expected .todo for separate-file emission")
            return
        }
    }

    /// The reason the guard lives in `isDeclined` (which `continue`s) rather
    /// than short-circuiting the whole strategy.
    @Test("a reachable initializer is still used when a restricted one exists")
    func reachableInitializerWins() {
        let subject = shape([
            initializer(["secret"], .private),
            initializer(["a", "b"], .public)
        ])
        guard case .initializerBased(let arguments) = DerivationStrategist
            .strategy(for: subject) else {
            Issue.record("expected the public initializer to be used")
            return
        }
        #expect(arguments.map(\.label) == ["a", "b"])
    }

    @Test("internal and wider initializers derive unchanged", arguments: [
        AccessLevel.internal, .package, .public
    ])
    func widerInitializersDerive(_ access: AccessLevel) {
        guard case .initializerBased = DerivationStrategist.strategy(
            for: shape([initializer(["a", "b"], access)])
        ) else {
            Issue.record("expected derivation for \(access)")
            return
        }
    }

    @Test("omitting the access level preserves the previous behaviour")
    func defaultedAccessIsBackCompatible() {
        let untyped = InitializerSignature(
            parameters: [InitializerParameter(label: "a", typeName: "Int")]
        )
        #expect(untyped.accessLevel == .internal)
    }

    /// Reporting "parameter types don't resolve" for two `Int`s would send the
    /// user to inspect the one thing that is fine.
    @Test("the todo reason names access, not parameter resolution")
    func todoReasonNamesAccess() {
        guard case .todo(let reason) = DerivationStrategist.strategy(
            for: shape([initializer(["a", "b"], .private)])
        ) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("every initializer the type declares is private"))
        #expect(reason.contains("Widen an initializer's access level"))
        #expect(reason.contains("all parameter types resolve") == false)
    }

    /// When only *some* initializers are restricted the failure is something
    /// else, and the catch-all message is the honest one.
    @Test("a mixed set falls back to the general initializer reason")
    func mixedSetUsesGeneralReason() {
        let subject = shape([
            initializer(["a"], .private),
            InitializerSignature(
                parameters: [InitializerParameter(label: "x", typeName: "Unresolvable")],
                accessLevel: .public
            )
        ])
        guard case .todo(let reason) = DerivationStrategist.strategy(for: subject) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("every initializer the type declares is") == false)
        #expect(reason.contains("don't support derivation"))
    }

    /// `takesPrivateStorage` and this rule catch different things and both
    /// still fire — a `public init(_bits:count:)` is callable and still unsound.
    @Test("the storage-parameter rule is unaffected by access")
    func storageRuleStillIndependent() {
        let storage = InitializerSignature(
            parameters: [
                InitializerParameter(label: "_bits", typeName: "Int"),
                InitializerParameter(label: "count", typeName: "Int")
            ],
            accessLevel: .public
        )
        #expect(DerivationStrategist.takesPrivateStorage(storage))
        guard case .todo = DerivationStrategist.strategy(for: shape([storage])) else {
            Issue.record("expected .todo from the storage rule")
            return
        }
    }
}
