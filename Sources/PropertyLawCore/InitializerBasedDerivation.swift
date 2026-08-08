/// Tier 6 — deriving a generator by lifting through a struct's user-defined
/// initializer. Memberwise derivation can't apply when a type declares its
/// own `init` (Swift drops the synthesized memberwise init), and that turned
/// out to be the single largest `.todo` category on real code. This file
/// holds the initializer model captured from SwiftSyntax and the strategist
/// step that consumes it; the `DerivationStrategy.initializerBased` case and
/// its emission live with the rest of the strategy machinery.

/// One parameter of a captured initializer — the call-site label (external
/// name, or the internal name when no external is given; `nil` for an
/// unlabeled `_` parameter) and the source-declared type spelling.
public struct InitializerParameter: Sendable, Equatable {
    public let label: String?
    public let typeName: String

    public init(label: String?, typeName: String) {
        self.label = label
        self.typeName = typeName
    }
}

/// A user-declared initializer captured from SwiftSyntax, consumed by the
/// Tier 6 `initializerBased` strategy. Failable and throwing inits are
/// flagged so the strategist can skip them — neither composes into a simple
/// value-producing generator.
public struct InitializerSignature: Sendable, Equatable {
    public let parameters: [InitializerParameter]
    public let isFailable: Bool
    public let isThrowing: Bool

    /// `true` when the body calls `assert` / `precondition` — the initializer has stated that
    /// its arguments must satisfy something. A derived generator draws arbitrary values, so
    /// calling such an initializer aborts the process rather than failing a law. See
    /// `InitializerPreconditionDetector`.
    public let assertsPrecondition: Bool

    /// `true` when the body delegates with `self.init(…)`, so any precondition on the target
    /// applies here too. See `InitializerPreconditionDetector.delegatesToSelf`.
    public let delegatesToSelf: Bool

    public init(
        parameters: [InitializerParameter],
        isFailable: Bool = false,
        isThrowing: Bool = false,
        assertsPrecondition: Bool = false,
        delegatesToSelf: Bool = false
    ) {
        self.parameters = parameters
        self.isFailable = isFailable
        self.isThrowing = isThrowing
        self.assertsPrecondition = assertsPrecondition
        self.delegatesToSelf = delegatesToSelf
    }
}

/// One argument of an initializer-based generator: the call-site label
/// (`nil` for an unlabeled `_` parameter) paired with the generator for the
/// parameter's type. Built by the strategist only after every parameter of a
/// chosen initializer has resolved to a generator.
public struct InitArgument: Sendable, Equatable {
    /// The label to spell at the call site, or `nil` for an unlabeled
    /// parameter (external name `_`).
    public let label: String?
    public let generatorExpression: String
    public let requiredImports: Set<String>

    public init(label: String?, generatorExpression: String, requiredImports: Set<String> = []) {
        self.label = label
        self.generatorExpression = generatorExpression
        self.requiredImports = requiredImports
    }
}

extension DerivationStrategist {

    /// Parameter labels that name a **capacity hint** rather than a value.
    ///
    /// An initializer whose every parameter is one of these constructs an *empty* value: the
    /// argument sizes the storage and contributes nothing to what the value IS. Deriving a
    /// generator through it produces a **constant** — the same empty collection every trial,
    /// dressed up as a hundred distinct ones.
    ///
    /// **Measured 2026-08-02 on swift-collections.** `Deque` declares
    /// `init(minimumCapacity: Int)` alongside `init<S: Sequence>(_ items: S)`. `Int` resolves
    /// and `S` does not, so the capacity hint was chosen, and the emitted generator was
    /// `Gen<Int>.int(in: -10_000...10_000).map { Deque(minimumCapacity: $0) }`. Two failures
    /// in one expression: every value is empty, and a negative capacity aborts the process —
    /// `failed to allocate 18446744073709521272 bytes`.
    ///
    /// **The constant is the worse half.** A crash is loud. A generator that yields one value
    /// a hundred times makes every law pass for the wrong reason, and a green suite is
    /// believed. Declining here returns the carrier to `.todo`, where the message already
    /// tells the user to supply `gen()` — which is true, and which the kit's own
    /// `PropertyLawCollections` recipes then satisfy.
    ///
    /// Rejection requires ALL parameters to be capacity-shaped. An initializer mixing a real
    /// value with a capacity hint still constructs something that varies, and is kept.
    public static let capacityHintLabels: Set<String> = [
        "capacity", "minimumCapacity", "initialCapacity",
        "reservingCapacity", "reserveCapacity"
    ]

    /// `true` when every parameter is a capacity hint, so the initializer cannot produce a
    /// value that varies with its arguments.
    static func isCapacityOnly(_ initializer: InitializerSignature) -> Bool {
        guard !initializer.parameters.isEmpty else { return false }
        return initializer.parameters.allSatisfy { parameter in
            guard let label = parameter.label else { return false }
            return capacityHintLabels.contains(label)
        }
    }

    /// **A capacity hint plus a flag is still a constant** — the ALL-parameters rule above was
    /// too strict, and the counterexample was measured rather than argued.
    ///
    /// `capacityHintLabels` documents its own limit: *"Rejection requires ALL parameters to be
    /// capacity-shaped. An initializer mixing a real value with a capacity hint still
    /// constructs something that varies, and is kept."* That assumption is false when the
    /// other parameter is a `Bool`, because a flag selects a storage STRATEGY and cannot
    /// supply contents.
    ///
    /// **Measured 2026-08-08 on swift-collections `c8080d05`.** `OrderedDictionary` declares
    /// `init(minimumCapacity: Int, persistent: Bool)`. Both parameter types resolve, the
    /// mixed-parameter escape hatch kept it, and the emitted generator was
    /// `zip(Gen<Int>.int(in: -10_000...10_000), Gen<Bool>.bool())
    /// .map { OrderedDictionary(minimumCapacity: $0.0, persistent: $0.1) }`. Every value is the
    /// **empty** dictionary; `Hashable.distribution` reported *"1000 samples produced only 1
    /// unique hashValues; last sample: `[:]`"* for `OrderedDictionary`, `.Elements` and
    /// `.Values` alike. The negative-capacity trap from the original measurement is present
    /// here too.
    ///
    /// **The distribution failure is the symptom, not the cost.** It is Heuristic-tier, so it
    /// does not fail a suite by itself — meanwhile the Equatable and Hashable laws over that
    /// carrier were *passing over a single value*. A vacuous pass is indistinguishable from a
    /// real one in a count of passing laws, which is the `f(x) == f(x)` failure mode wearing a
    /// generator.
    ///
    /// Scoped to `Bool` deliberately, rather than "any parameter that is not a collection". A
    /// numeric alongside a capacity hint may well be a real component (`init(capacity:seed:)`
    /// for a hash), and declining it would trade a measured false positive for an unmeasured
    /// false negative — the direction this project does not take.
    static func isCapacityWithFlagsOnly(_ initializer: InitializerSignature) -> Bool {
        let labels = initializer.parameters.map(\.label)
        guard labels.contains(where: { $0.map(capacityHintLabels.contains) ?? false }) else {
            return false
        }
        return initializer.parameters.allSatisfy { parameter in
            if let label = parameter.label, capacityHintLabels.contains(label) { return true }
            return parameter.typeName == "Bool"
        }
    }

    /// **An initializer that takes the type's private storage is not a value constructor.**
    ///
    /// A parameter label beginning with `_` names an implementation detail. Such an
    /// initializer assigns the representation directly, which means its arguments must
    /// **jointly** satisfy an invariant it does not establish — and a derived generator draws
    /// each parameter *independently*.
    ///
    /// **Measured 2026-08-08 on swift-collections `c8080d05`.** `BitSet.Counted` declares
    /// `internal init(_bits: BitSet, count: Int)`, whose body ends in `_checkInvariants()`.
    /// The derived generator drew `count` from `-10_000...10_000` with no relation to `_bits`,
    /// so it built values whose count contradicts their contents — and the emitted suite then
    /// reported `SetAlgebra.unionIdempotence` (Strict, trial 1),
    /// `Sequence.underestimatedCountLowerBound` (Strict) and `Codable.roundTripFidelity[JSON]`
    /// (Conventional) as **violated on correct swift-collections code**. Three false
    /// refutations against a library that is not wrong.
    ///
    /// **This is the `@testable` hazard, and the label is the cheapest sound signal for it.**
    /// A consumer generating suites imports the module `@testable`, which makes internal
    /// storage constructors callable that no public caller could reach. Access level would be
    /// the more direct test, but `InitializerSignature` does not carry it and inventing the
    /// field is a larger change than the evidence needs: `_checkInvariants()` is also not
    /// recognised by `InitializerPreconditionDetector`, so neither existing gate fires.
    ///
    /// The rule is **conservative in the safe direction**. Declining returns the carrier to
    /// `.todo`, whose message already asks for a `gen()` — a carrier nobody can generate is a
    /// gap, while a carrier generated wrongly is a lie about somebody else's library.
    ///
    /// **The arity requirement is the whole rule, not a softening of it.** The defect is
    /// *independence between* parameters: a generator draws each one separately, so it can
    /// build a `count` that contradicts its `_bits`. A **single**-parameter initializer has
    /// nothing to be inconsistent with — its argument fully determines the value — so
    /// declining one buys no soundness and costs real coverage.
    ///
    /// Measured, on the first version of this rule which omitted the arity test:
    /// `OrderedSet.UnorderedView(_base:)`, `OrderedDictionary.Values(_base:)` and
    /// `.Elements(_base:)` are single-parameter wrappers around a value that generates
    /// perfectly well, and all three stopped deriving — **10 of 26 emitted tests lost** on
    /// swift-collections for no gain. With the arity test they derive again, and
    /// `BitSet.Counted(_bits:count:)` stays declined.
    ///
    /// Two parameters is where it starts to bite correctly, and the second witness confirms
    /// the direction rather than the letter: `OrderedDictionary.Elements.SubSequence(_base:
    /// bounds:)` pairs a base with a `Range` that must lie inside it, which independent draws
    /// cannot honour. That one *should* decline, and does.
    ///
    /// **NARROWED 2026-08-08 — arity alone still over-reached, and NIO paid for it.**
    /// `NIOAsyncWriterError(_code:file:line:)` has three parameters and an `_`-prefixed label,
    /// and is perfectly sound: its `==` and `hash` key only on `_code`, and a code, a file and
    /// a line constrain each other in no way at all. The rule declined it, costing one carrier
    /// and four laws on `NIOCore` — measured and reported as the price of the first version,
    /// then paid back here.
    ///
    /// What separates it from the true positives is not the storage parameter but **what the
    /// OTHER parameters are**. In both witnesses they are *measurements of the storage*:
    /// `count` is the size of `_bits`, `bounds` is a range of positions into `_base`. Those
    /// must agree with the aggregate, and independent draws cannot make them agree. NIO's
    /// `file` and `line` describe the source that raised the error, not the value beside them.
    ///
    /// So the rule needs **both halves**: a storage parameter *and* a parameter naming a
    /// property that storage determines.
    static func takesPrivateStorage(_ initializer: InitializerSignature) -> Bool {
        guard initializer.parameters.count > 1 else { return false }
        let labels = initializer.parameters.compactMap(\.label)
        guard labels.contains(where: { $0.hasPrefix("_") }) else { return false }
        return labels.contains { storageMeasurementLabels.contains($0) }
    }

    /// Parameter labels naming a property that an aggregate **determines** — its size, or a
    /// position within it.
    ///
    /// Beside a storage parameter these cannot be drawn independently: `count` must equal the
    /// storage's count, `bounds` must lie inside its indices. That is the joint invariant a
    /// derived generator breaks.
    ///
    /// Curated rather than inferred, in the same style and for the same reason as
    /// `capacityHintLabels` — deciding whether one parameter's value is computable from
    /// another's is static analysis this tier does not do, while the *names* library authors
    /// give these things are stable and few. Each entry is a property OF a container rather
    /// than a component of a value: an initializer taking a `count` beside private storage is
    /// restating something the storage already says.
    ///
    /// The witnesses that set the list are `BitSet.Counted(_bits:count:)` and
    /// `OrderedDictionary.Elements.SubSequence(_base:bounds:)`; the rest are the same idea
    /// under the spellings the standard library and swift-collections use for it.
    public static let storageMeasurementLabels: Set<String> = [
        "count", "bounds", "range", "indices", "length", "size",
        "startIndex", "endIndex", "offset", "position"
    ]

    /// Every reason to pass over an initializer before trying to resolve its parameters.
    ///
    /// Extracted 2026-08-02 when the precondition gates took `initializerBasedStrategy` past
    /// the cyclomatic-complexity cap. Worth having as one named predicate regardless: the
    /// list is the accumulated record of what a derived generator must not call, and each
    /// entry cost a measured failure to learn.
    static func isDeclined(_ initializer: InitializerSignature, in shape: TypeShape) -> Bool {
        if initializer.isFailable || initializer.isThrowing { return true }
        if initializer.parameters.isEmpty { return true }
        if initializer.parameters.count > memberwiseMemberLimit { return true }
        // A capacity-only initializer resolves (its parameters are `Int`) and derives a
        // CONSTANT — see `capacityHintLabels`.
        if isCapacityOnly(initializer) { return true }
        // …and so does a capacity hint paired only with flags: `OrderedDictionary
        // (minimumCapacity:persistent:)` derived 1000 samples with 1 unique hash.
        if isCapacityWithFlagsOnly(initializer) { return true }
        // An `_`-prefixed label takes the type's private storage, so the arguments must
        // jointly hold an invariant a generator drawing them independently cannot.
        // `BitSet.Counted(_bits:count:)` produced three FALSE refutations against correct
        // swift-collections code.
        if takesPrivateStorage(initializer) { return true }
        // The initializer has said its arguments must satisfy something, and a derived
        // generator draws arbitrary ones. Three swift-collections carriers aborted the whole
        // suite on `assert(offset >= 0)`. See `InitializerPreconditionDetector` for why this
        // declines instead of trying to satisfy the condition.
        if initializer.assertsPrecondition { return true }
        // A delegating initializer inherits its target's precondition. `_HeapNode`'s
        // `init(offset:)` asserts nothing and forwards to `init(offset:level:)`, which
        // asserts `offset >= 0` — a body-only check calls it clean and the suite still
        // aborts. Overload resolution is out of scope, so the test is "delegates AND some
        // initializer on this type asserts", which cannot admit a dirty target.
        if initializer.delegatesToSelf, shape.initializers.contains(where: { $0.assertsPrecondition }) {
            return true
        }
        return false
    }

    /// Tier 6 — derive through a user-defined initializer. Runs only after
    /// `memberwiseStrategy` declines (which it does whenever the struct has a
    /// user `init`). Picks the first captured initializer that is
    /// non-failable, non-throwing, has 1–`memberwiseArityLimit` parameters,
    /// and whose every parameter type resolves to a generator. Returns `nil`
    /// (not `.todo`) so `strategy(for:)` can fall through to later candidates.
    static func initializerBasedStrategy(
        for shape: TypeShape,
        resolve: CustomTypeResolver = { _ in nil }
    ) -> DerivationStrategy? {
        guard shape.kind == .struct else { return nil }
        for initializer in shape.initializers {
            guard !isDeclined(initializer, in: shape) else { continue }
            var arguments: [InitArgument] = []
            var allResolved = true
            for parameter in initializer.parameters {
                guard let composed = composedGenerator(forTypeName: parameter.typeName, resolve: resolve) else {
                    allResolved = false
                    break
                }
                arguments.append(InitArgument(
                    label: parameter.label,
                    generatorExpression: composed.expression,
                    requiredImports: composed.requiredImports
                ))
            }
            if allResolved {
                return .initializerBased(arguments: arguments)
            }
        }
        return nil
    }
}
