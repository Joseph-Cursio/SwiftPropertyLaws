/// Tier 4 — deriving a generator for an enum with cases (payload-bearing or
/// plain, but not `CaseIterable`/raw-representable). Each case becomes a
/// `Generator<T>`; the cases combine with `Gen.oneOf(...)`. This fills the
/// "enum without CaseIterable/raw" `.todo` bucket — the largest addressable
/// gap on value-type-heavy code.

/// One enum case captured from SwiftSyntax: its name and associated values
/// (each a label + type spelling, reusing `InitializerParameter` — an enum
/// associated value is constructed exactly like a labeled init argument).
public struct EnumCase: Sendable, Equatable {
    public let name: String
    public let associatedValues: [InitializerParameter]

    public init(name: String, associatedValues: [InitializerParameter] = []) {
        self.name = name
        self.associatedValues = associatedValues
    }
}

/// A single resolved case generator: the case name plus a generator per
/// associated value (empty for a payload-free case). Built by the strategist
/// only after every associated value of every case has resolved.
public struct EnumCaseGenerator: Sendable, Equatable {
    public let caseName: String
    public let arguments: [InitArgument]

    public init(caseName: String, arguments: [InitArgument] = []) {
        self.caseName = caseName
        self.arguments = arguments
    }
}

extension DerivationStrategist {

    /// Tier 4 — derive an enum from its cases. Runs after `caseIterable` and
    /// `rawRepresentable` decline, so those enums keep their simpler
    /// strategies. Requires every case's associated values to resolve to
    /// generators and each case to stay within the `zip` arity limit;
    /// otherwise returns `nil` (the enum can't be partially represented — a
    /// `oneOf` must cover every case).
    static func enumCasesStrategy(
        for shape: TypeShape,
        resolve: CustomTypeResolver = { _ in nil }
    ) -> DerivationStrategy? {
        guard shape.kind == .enum else { return nil }
        guard !shape.enumCases.isEmpty else { return nil }

        var generators: [EnumCaseGenerator] = []
        for enumCase in shape.enumCases {
            guard enumCase.associatedValues.count <= memberwiseArityLimit else { return nil }
            var arguments: [InitArgument] = []
            for value in enumCase.associatedValues {
                guard let composed = composedGenerator(forTypeName: value.typeName, resolve: resolve) else {
                    return nil
                }
                arguments.append(InitArgument(
                    label: value.label,
                    generatorExpression: composed.expression,
                    requiredImports: composed.requiredImports
                ))
            }
            generators.append(EnumCaseGenerator(caseName: enumCase.name, arguments: arguments))
        }
        return .enumCases(cases: generators)
    }
}

/// Renders a `DerivationStrategy.enumCases` strategy to its
/// `swift-property-based` expression. A single case is emitted directly; two
/// or more combine via `Gen.oneOf(...)`, each case erased to a common
/// shrinker type with `.eraseToAny()` (the proven homogeneous-`oneOf` form).
enum EnumCaseEmitter {

    static func expression(typeName: String, cases: [EnumCaseGenerator]) -> String {
        precondition(!cases.isEmpty, "enum emitter requires ≥1 case")
        let caseGenerators = cases.map { caseGenerator(typeName: typeName, enumCase: $0) }
        if caseGenerators.count == 1 {
            return caseGenerators[0]
        }
        let body = caseGenerators
            .map { "    \($0).eraseToAny()" }
            .joined(separator: ",\n")
        return "Gen.oneOf(\n\(body)\n)"
    }

    /// Generator for one case: `Gen.always(T.c)` when payload-free, else the
    /// shared `zip(...).map { T.c(...) }` composer with the case constructor
    /// `T.c` as the "type name".
    private static func caseGenerator(typeName: String, enumCase: EnumCaseGenerator) -> String {
        let constructor = "\(typeName).\(enumCase.caseName)"
        if enumCase.arguments.isEmpty {
            return "Gen.always(\(constructor))"
        }
        return MemberwiseEmitter.compose(
            typeName: constructor,
            arguments: enumCase.arguments.map { (label: $0.label, expression: $0.generatorExpression) }
        )
    }
}
