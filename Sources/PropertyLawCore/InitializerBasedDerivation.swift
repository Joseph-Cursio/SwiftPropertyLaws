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
