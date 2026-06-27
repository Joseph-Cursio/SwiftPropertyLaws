/// Renders a `DerivationStrategy.memberwiseArbitrary(members:)` strategy
/// to the Swift expression text the macro, the discovery plugin, and
/// downstream emitters spell at every `using:` argument site. Pure
/// string formatting — kept in `PropertyLawCore` so every consumer
/// produces byte-identical output.
///
/// One expression shape covers all valid member counts (1 through 10):
///
///     // 1 member:
///     Gen<Int>.int().map { TypeName(value: $0) }
///
///     // 2+ members (zip + tuple-positional map):
///     zip(Gen<Int>.int(), Gen<Int>.int())
///         .map { TypeName(easting: $0.0, northing: $0.1) }
///
/// The 2+ shape uses the single-arg `Generator.map` overload that
/// receives the tuple as `$0` and reads positional fields with `$0.N`,
/// because `swift-property-based` only ships the tuple-destructuring map
/// overload at 2-arity. Using `$0.N` for all 2+ cases keeps the emit
/// shape uniform across arities.
///
/// Promoted from `package` to `public` in the v1.7 K-prep-M1 cluster
/// so SwiftInferProperties M5's lifted-test stub writeout can call
/// the same emitter the macro / plugin use, instead of duplicating
/// the logic and accruing drift the way M3.4's `MemberBlockInspector`
/// port does.
public enum MemberwiseEmitter {

    public static func expression(typeName: String, members: [MemberSpec]) -> String {
        compose(
            typeName: typeName,
            arguments: members.map { (label: $0.name, expression: $0.generatorExpression) }
        )
    }

    /// Shared `zip(...).map { Type(...) }` composer for any list of labeled
    /// generators — used by memberwise derivation (labels = stored-property
    /// names) and the Tier 6 `initializerBased` strategy (labels = init
    /// argument labels, `nil` for unlabeled `_` parameters). Output is
    /// byte-identical to the previous memberwise emitter for non-nil labels.
    static func compose(
        typeName: String,
        arguments: [(label: String?, expression: String)]
    ) -> String {
        precondition(!arguments.isEmpty, "emitter requires ≥1 argument")
        precondition(
            arguments.count <= DerivationStrategist.memberwiseArityLimit,
            "emitter supports up to \(DerivationStrategist.memberwiseArityLimit) arguments"
        )
        if arguments.count == 1 {
            return "\(arguments[0].expression)"
                + ".map { \(typeName)(\(callArgument(arguments[0], value: "$0"))) }"
        }
        let generators = arguments.map(\.expression).joined(separator: ", ")
        let callArguments = arguments.enumerated()
            .map { index, argument in callArgument(argument, value: "$0.\(index)") }
            .joined(separator: ", ")
        return "zip(\(generators))\n            .map { \(typeName)(\(callArguments)) }"
    }

    private static func callArgument(
        _ argument: (label: String?, expression: String),
        value: String
    ) -> String {
        if let label = argument.label {
            return "\(label): \(value)"
        }
        return value
    }
}
