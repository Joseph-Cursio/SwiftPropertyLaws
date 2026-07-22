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
            arguments.count <= DerivationStrategist.memberwiseMemberLimit,
            "emitter supports up to \(DerivationStrategist.memberwiseMemberLimit) arguments"
        )
        if arguments.count == 1 {
            return "\(arguments[0].expression)"
                + ".map { \(typeName)(\(callArgument(arguments[0], value: "$0"))) }"
        }
        if arguments.count <= DerivationStrategist.memberwiseArityLimit {
            return flatZip(typeName: typeName, arguments: arguments)
        }
        return nestedZip(typeName: typeName, arguments: arguments)
    }

    /// The flat 2–10 shape: `zip(g0, …).map { T(l0: $0.0, …) }`. Byte-identical
    /// to the pre-nesting emitter.
    private static func flatZip(
        typeName: String,
        arguments: [(label: String?, expression: String)]
    ) -> String {
        let generators = arguments.map(\.expression).joined(separator: ", ")
        let callArguments = arguments.enumerated()
            .map { index, argument in callArgument(argument, value: "$0.\(index)") }
            .joined(separator: ", ")
        return "zip(\(generators))\n            .map { \(typeName)(\(callArguments)) }"
    }

    /// The 11–100 shape: chunk into groups of ≤`memberwiseArityLimit`, `zip` each
    /// group, `zip` the groups, then `.map` reading `$0.group.position` (or
    /// `$0.group` for a lone-member group, which isn't a tuple). Swift tuples have
    /// no arity ceiling, so only `zip` itself is bounded — hence the nesting.
    ///
    ///     zip(zip(g0, …, g9), g10)
    ///                 .map { T(m0: $0.0.0, …, m9: $0.0.9, m10: $0.1) }
    private static func nestedZip(
        typeName: String,
        arguments: [(label: String?, expression: String)]
    ) -> String {
        let groupSize = DerivationStrategist.memberwiseArityLimit
        let groups = stride(from: 0, to: arguments.count, by: groupSize).map { start in
            Array(arguments[start ..< min(start + groupSize, arguments.count)])
        }
        let groupGenerators = groups.map { group in
            group.count == 1
                ? group[0].expression
                : "zip(\(group.map(\.expression).joined(separator: ", ")))"
        }
        var callArguments: [String] = []
        for (groupIndex, group) in groups.enumerated() {
            for (position, argument) in group.enumerated() {
                let value = group.count == 1 ? "$0.\(groupIndex)" : "$0.\(groupIndex).\(position)"
                callArguments.append(callArgument(argument, value: value))
            }
        }
        return "zip(\(groupGenerators.joined(separator: ", ")))"
            + "\n            .map { \(typeName)(\(callArguments.joined(separator: ", "))) }"
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
