import SwiftSyntax

/// Walks a `MemberBlockSyntax` and OR-merges the structural witnesses
/// that `AdvisorySuggester` consumes (PRD §5.4 missing-conformance
/// suggestions, M4 scope).
///
/// Witness detection is deliberately syntactic: signature shape only,
/// no type resolution. False positives are possible but rare for the
/// specific signatures we look for, and the suggester only emits
/// HIGH-confidence advice by default — see PRD §8 ("less than 5%
/// false-positive Strong-confidence suggestions").
enum WitnessFinder {

    static func find(in memberBlock: MemberBlockSyntax) -> WitnessSet {
        var result = WitnessSet()
        for member in memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                inspect(funcDecl, into: &result)
            }
            if let initDecl = member.decl.as(InitializerDeclSyntax.self) {
                inspectInit(initDecl, into: &result)
            }
        }
        return result
    }

    private static func inspect(
        _ funcDecl: FunctionDeclSyntax,
        into result: inout WitnessSet
    ) {
        let name = funcDecl.name.text
        let isStatic = funcDecl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static)
        }
        let parameters = funcDecl.signature.parameterClause.parameters

        // `static func ==(lhs:rhs:) -> Bool`. We don't inspect parameter
        // types — `static func ==` is unambiguous in Swift; only the
        // Equatable witness uses that name.
        if isStatic, name == "==" {
            result.hasEqualEqualOperator = true
        }

        // `static func <(lhs:rhs:) -> Bool` — same logic.
        if isStatic, name == "<" {
            result.hasLessThanOperator = true
        }

        // `func hash(into hasher: inout Hasher)` — match on the name and
        // the single `into:` first parameter label. The Hashable witness
        // is unambiguous at that shape.
        if !isStatic, name == "hash", parameters.count == 1,
           let first = parameters.first,
           first.firstName.text == "into" {
            result.hasHashIntoMethod = true
        }

        // `func encode(to encoder: Encoder) throws` — Encodable half of
        // the Codable pair.
        if !isStatic, name == "encode", parameters.count == 1,
           let first = parameters.first,
           first.firstName.text == "to" {
            result.hasEncodeToMethod = true
        }
    }

    /// `init(from decoder: Decoder) throws` — Decodable half of the
    /// Codable pair.
    private static func inspectInit(
        _ initDecl: InitializerDeclSyntax,
        into result: inout WitnessSet
    ) {
        let parameters = initDecl.signature.parameterClause.parameters
        if parameters.count == 1,
           let first = parameters.first,
           first.firstName.text == "from" {
            result.hasInitFromInitializer = true
        }
    }
}
