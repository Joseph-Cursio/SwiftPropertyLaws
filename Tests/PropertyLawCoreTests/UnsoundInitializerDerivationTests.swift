import Testing
@testable import PropertyLawCore

/// **Two derived generators that produced WRONG suites, both measured on swift-collections
/// `c8080d05` on 2026-08-08, and both reproduced here at the shape level.**
///
/// They fail in opposite directions, which is why they are one file: one made a correct
/// library look broken, the other made an untested carrier look tested. The second is the
/// more dangerous and the harder to notice.
///
/// - `BitSet.Counted(_bits:count:)` — the derived generator drew `count`
///   independently of `_bits`, and the suite reported three laws **violated**
///   on correct code.
/// - `OrderedDictionary(minimumCapacity:persistent:)` — the derived generator
///   produced the empty dictionary every trial, and every law **passed**, over
///   that one value.
struct UnsoundInitializerDerivationTests {

    private func shape(_ name: String, _ initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable", "Hashable"],
            hasUserGen: false,
            storedMembers: [],
            hasUserInit: true,
            initializers: initializers
        )
    }

    private func parameter(_ label: String?, _ typeName: String) -> InitializerParameter {
        InitializerParameter(label: label, typeName: typeName)
    }

    // MARK: - Private storage

    /// `BitSet.Counted`, reduced. Both parameter types resolve, so without the gate this
    /// derives and draws a `count` unrelated to the bits.
    @Test("an initializer taking private storage does not derive")
    func privateStorageDeclines() {
        let strategy = DerivationStrategist.strategy(
            for: shape("Counted", [InitializerSignature(parameters: [
                parameter("_bits", "Int"), parameter("count", "Int")
            ])])
        )
        guard case .todo = strategy else {
            Issue.record("expected .todo, got \(strategy) — a storage constructor derived")
            return
        }
    }

    /// The gate keys on the **label**, which is what distinguishes a storage constructor from
    /// an ordinary one. A type whose stored property happens to be underscored but whose
    /// initializer labels are not is unaffected.
    @Test("an ordinary initializer with the same types still derives")
    func ordinaryInitializerSurvives() {
        let strategy = DerivationStrategist.strategy(
            for: shape("Money", [InitializerSignature(parameters: [
                parameter("units", "Int"), parameter("count", "Int")
            ])])
        )
        if case .todo = strategy {
            Issue.record("the gate over-reached: a normal two-Int initializer stopped deriving")
        }
    }

    /// An unlabeled parameter (`init(_ value: Int)`) records `nil`, not `"_"`. It must not be
    /// mistaken for a storage label — that spelling is the single commonest initializer in
    /// Swift and declining it would empty the tier.
    @Test("an unlabeled parameter is not a storage label")
    func unlabelledParameterIsNotStorage() {
        #expect(!DerivationStrategist.takesPrivateStorage(
            InitializerSignature(parameters: [parameter(nil, "Int")])
        ))
        let strategy = DerivationStrategist.strategy(
            for: shape("Meters", [InitializerSignature(parameters: [parameter(nil, "Int")])])
        )
        if case .todo = strategy {
            Issue.record("init(_ value:) must still derive")
        }
    }

    /// **A single-parameter wrapper has no joint invariant to violate**, so declining it buys
    /// no soundness. Measured: the first version of this rule omitted the arity test and cost
    /// `UnorderedView(_base:)`, `.Values(_base:)` and `.Elements(_base:)` — 10 of 26 emitted
    /// swift-collections tests — for nothing.
    @Test("a single-parameter storage wrapper still derives")
    func singleParameterWrapperSurvives() {
        let initializer = InitializerSignature(parameters: [parameter("_base", "Int")])
        #expect(!DerivationStrategist.takesPrivateStorage(initializer))
        let strategy = DerivationStrategist.strategy(for: shape("UnorderedView", [initializer]))
        if case .todo = strategy {
            Issue.record("a single-parameter wrapper must keep deriving")
        }
    }

    /// The direction the arity rule is really about: two parameters that must AGREE.
    /// `.Elements.SubSequence(_base:bounds:)` pairs a base with a range that must lie inside
    /// it, which independent draws cannot honour.
    @Test("a storage base paired with bounds does not derive")
    func storageWithBoundsDeclines() {
        #expect(DerivationStrategist.takesPrivateStorage(
            InitializerSignature(parameters: [
                parameter("_base", "Int"), parameter("bounds", "Int")
            ])
        ))
    }

    /// **The NIOCore false positive, and the reason the rule needs two halves.**
    /// `NIOAsyncWriterError(_code:file:line:)` has three parameters and an `_` label, and is
    /// sound — its `==` and `hash` key only on `_code`, and a code, a file and a line
    /// constrain each other in no way. The arity-only rule declined it, costing one carrier
    /// and four laws on NIOCore.
    @Test("a storage label beside unrelated metadata still derives")
    func storageWithUnrelatedMetadataSurvives() {
        let initializer = InitializerSignature(parameters: [
            parameter("_code", "Int"), parameter("file", "String"), parameter("line", "Int")
        ])
        #expect(!DerivationStrategist.takesPrivateStorage(initializer))
        let strategy = DerivationStrategist.strategy(
            for: shape("NIOAsyncWriterError", [initializer])
        )
        if case .todo = strategy {
            Issue.record("independent parameters beside a storage label must keep deriving")
        }
    }

    /// `line` is an `Int` sitting beside a storage parameter, exactly as `count` is — so the
    /// rule cannot key on the TYPE. It keys on the label, and this pins that distinction.
    @Test("the rule keys on the label, not on the parameter type")
    func numericAloneIsNotAMeasurement() {
        #expect(!DerivationStrategist.takesPrivateStorage(
            InitializerSignature(parameters: [parameter("_code", "Int"), parameter("line", "Int")])
        ))
        #expect(DerivationStrategist.takesPrivateStorage(
            InitializerSignature(parameters: [parameter("_bits", "Int"), parameter("count", "Int")])
        ))
    }

    /// A measurement label with no storage parameter is an ordinary component — `init(count:)`
    /// on a value type describes the value rather than restating an aggregate.
    @Test("a measurement label without storage is untouched")
    func measurementAloneSurvives() {
        #expect(!DerivationStrategist.takesPrivateStorage(
            InitializerSignature(parameters: [
                parameter("count", "Int"), parameter("name", "String")
            ])
        ))
    }

    // MARK: - Capacity plus flags

    /// `OrderedDictionary(minimumCapacity:persistent:)`, reduced. The pre-existing
    /// `isCapacityOnly` rule does NOT fire here — that is the hole this closes.
    @Test("a capacity hint paired with a flag does not derive")
    func capacityWithFlagDeclines() {
        let initializer = InitializerSignature(parameters: [
            parameter("minimumCapacity", "Int"), parameter("persistent", "Bool")
        ])
        #expect(
            !DerivationStrategist.isCapacityOnly(initializer),
            "the old rule must not fire — otherwise this test proves nothing about the new one"
        )
        let strategy = DerivationStrategist.strategy(for: shape("OrderedDictionary", [initializer]))
        guard case .todo = strategy else {
            Issue.record("expected .todo, got \(strategy) — a constant generator derived")
            return
        }
    }

    /// The scope line from `isCapacityWithFlagsOnly`: a numeric beside a capacity hint may be
    /// a real component, and declining it would trade a measured false positive for an
    /// unmeasured false negative.
    @Test("a capacity hint beside a real component still derives")
    func capacityWithComponentSurvives() {
        let strategy = DerivationStrategist.strategy(
            for: shape("Table", [InitializerSignature(parameters: [
                parameter("minimumCapacity", "Int"), parameter("seed", "Int")
            ])])
        )
        if case .todo = strategy {
            Issue.record("the gate over-reached: a capacity hint plus a seed stopped deriving")
        }
    }

    /// A flag on its own says nothing about emptiness — only the pairing does. Without this,
    /// the rule would decline every `init(flag: Bool)` in the corpus.
    @Test("flags alone are untouched")
    func flagsAloneSurvive() {
        #expect(!DerivationStrategist.isCapacityWithFlagsOnly(
            InitializerSignature(parameters: [parameter("persistent", "Bool")])
        ))
    }

    // MARK: - The two gates are independent

    /// Each witness must be caught by its OWN rule. If either passed only because the other
    /// fired, removing one would silently reopen a defect.
    @Test("each witness is caught by its own gate")
    func gatesAreIndependent() {
        let counted = InitializerSignature(parameters: [
            parameter("_bits", "Int"), parameter("count", "Int")
        ])
        #expect(DerivationStrategist.takesPrivateStorage(counted))
        #expect(!DerivationStrategist.isCapacityWithFlagsOnly(counted))

        let dictionary = InitializerSignature(parameters: [
            parameter("minimumCapacity", "Int"), parameter("persistent", "Bool")
        ])
        #expect(DerivationStrategist.isCapacityWithFlagsOnly(dictionary))
        #expect(!DerivationStrategist.takesPrivateStorage(dictionary))
    }
}
