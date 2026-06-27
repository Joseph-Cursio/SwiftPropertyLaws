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
        precondition(!members.isEmpty, "memberwise emitter requires ≥1 member")
        precondition(
            members.count <= DerivationStrategist.memberwiseArityLimit,
            "memberwise emitter supports up to "
                + "\(DerivationStrategist.memberwiseArityLimit) members"
        )
        if members.count == 1 {
            return singleMemberExpression(typeName: typeName, member: members[0])
        }
        return zipExpression(typeName: typeName, members: members)
    }

    private static func singleMemberExpression(typeName: String, member: MemberSpec) -> String {
        "\(member.generatorExpression)"
            + ".map { \(typeName)(\(member.name): $0) }"
    }

    private static func zipExpression(typeName: String, members: [MemberSpec]) -> String {
        let generators = members
            .map(\.generatorExpression)
            .joined(separator: ", ")
        let arguments = members.enumerated()
            .map { index, member in "\(member.name): $0.\(index)" }
            .joined(separator: ", ")
        return "zip(\(generators))\n            .map { \(typeName)(\(arguments)) }"
    }
}
