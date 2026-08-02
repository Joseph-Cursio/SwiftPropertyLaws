import Testing
@testable import PropertyLawCore

/// A capacity hint sizes storage; it does not describe a value. Deriving a generator through
/// `init(minimumCapacity:)` produces the same EMPTY collection every trial, so every law
/// passes for the wrong reason.
///
/// **Measured 2026-08-02 on swift-collections.** `Deque` declares both
/// `init(minimumCapacity: Int)` and `init<S: Sequence>(_ items: S)`. `Int` resolves and `S`
/// does not, so the capacity hint won and the emitted generator was
/// `Gen<Int>.int(in: -10_000...10_000).map { Deque(minimumCapacity: $0) }` — every value
/// empty, and negative capacities aborting the process outright
/// (`failed to allocate 18446744073709521272 bytes`).
///
/// The crash is the loud half and the constant is the dangerous one: a suite that cannot
/// fail is believed.
struct CapacityHintDerivationTests {

    private func shape(_ name: String, _ initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [],
            hasUserInit: true,
            initializers: initializers
        )
    }

    private func capacityInit(_ label: String) -> InitializerSignature {
        InitializerSignature(parameters: [InitializerParameter(label: label, typeName: "Int")])
    }

    /// The `Deque` case, reduced. Without the gate this derives and yields a constant.
    @Test("a capacity-only initializer does not derive")
    func capacityOnlyDeclines() {
        let strategy = DerivationStrategist.strategy(
            for: shape("Deque", [capacityInit("minimumCapacity")])
        )
        guard case .todo = strategy else {
            Issue.record("expected .todo, got \(strategy) — a capacity hint derived a constant")
            return
        }
    }

    @Test("every capacity spelling is rejected")
    func allSpellingsDeclined() {
        for label in DerivationStrategist.capacityHintLabels {
            let strategy = DerivationStrategist.strategy(for: shape("Sized", [capacityInit(label)]))
            guard case .todo = strategy else {
                Issue.record("`\(label)` derived a constant generator")
                continue
            }
        }
    }

    /// The gate is ALL-parameters, not any. An initializer mixing a real value with a
    /// capacity hint still constructs something that varies, and must keep deriving —
    /// otherwise the fix trades a false generator for a false `.todo`.
    @Test("a capacity hint ALONGSIDE a real value still derives")
    func mixedInitializerStillDerives() {
        let mixed = InitializerSignature(parameters: [
            InitializerParameter(label: "name", typeName: "String"),
            InitializerParameter(label: "minimumCapacity", typeName: "Int")
        ])
        let strategy = DerivationStrategist.strategy(for: shape("Buffer", [mixed]))
        if case .todo = strategy {
            Issue.record("a mixed initializer must still derive — the value parameter varies")
        }
    }

    /// A later initializer must still be reachable: skipping the capacity one is a `continue`,
    /// not a bail-out for the whole type.
    @Test("a capacity initializer does not block a usable one behind it")
    func laterInitializerStillWins() {
        let usable = InitializerSignature(
            parameters: [InitializerParameter(label: nil, typeName: "Int")]
        )
        let strategy = DerivationStrategist.strategy(
            for: shape("Counter", [capacityInit("capacity"), usable])
        )
        if case .todo = strategy {
            Issue.record("the usable initializer after the capacity one was not reached")
        }
    }

    /// An unlabelled `Int` parameter is a value, not a capacity — the gate keys on the label
    /// and must not reject on type alone.
    @Test("an unlabelled Int parameter is not treated as a capacity hint")
    func unlabelledParameterIsAValue() {
        let unlabelled = InitializerSignature(
            parameters: [InitializerParameter(label: nil, typeName: "Int")]
        )
        let strategy = DerivationStrategist.strategy(for: shape("Wrapper", [unlabelled]))
        if case .todo = strategy {
            Issue.record("an unlabelled Int is a value and must still derive")
        }
    }
}
