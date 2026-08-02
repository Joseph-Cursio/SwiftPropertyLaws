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

    public init(parameters: [InitializerParameter], isFailable: Bool = false, isThrowing: Bool = false) {
        self.parameters = parameters
        self.isFailable = isFailable
        self.isThrowing = isThrowing
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
            guard !initializer.isFailable, !initializer.isThrowing else { continue }
            guard !initializer.parameters.isEmpty else { continue }
            guard initializer.parameters.count <= memberwiseMemberLimit else { continue }
            // A capacity-only initializer resolves (its parameters are `Int`) and derives a
            // CONSTANT — see `capacityHintLabels`. Skipped before resolution so a later
            // initializer, or `.todo`, wins instead.
            guard !isCapacityOnly(initializer) else { continue }
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
