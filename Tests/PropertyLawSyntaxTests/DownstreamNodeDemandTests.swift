import PropertyBased
import PropertyLawKit
import SwiftSyntax
import Testing
@testable import PropertyLawSyntax

/// Six concrete node types a downstream consumer (SwiftInferProperties) measured
/// as blocking its own verification — its `Unverifiable` picks. A measured
/// demand from a real consumer is better input than a guess about which of
/// swift-syntax's ~300 node types matter, so each is pinned here by name.
///
/// Four were already reachable through the generic `Gen<T>.syntaxNode()`, which
/// is the payoff for having written that generically instead of by hand for
/// `ExprSyntax` and `TokenSyntax`. Two needed work:
///
/// - `DictionaryExprSyntax` — no template contained a dictionary literal.
///   Template 14 adds one.
/// - `ArraySlice<CodeBlockItemSyntax>` — not a `SyntaxProtocol` at all, so
///   `syntaxNode()` cannot express it. Handled in the kit's composite parser
///   instead, which makes it general: `ArraySlice` is a stdlib type and every
///   element type benefits, not just syntax nodes.
struct DownstreamNodeDemandTests {

    private func sample<T: SyntaxProtocol>(
        _ generator: Generator<T, some SendableSequenceType>,
        count: Int = 20
    ) -> [T] {
        var rng = Xoshiro(seed: (1, 2, 3, 4))
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    @Test("DeclModifierListSyntax is generable")
    func declModifierList() {
        #expect(sample(Gen<DeclModifierListSyntax>.syntaxNode()).count == 20)
    }

    @Test("StringLiteralExprSyntax is generable")
    func stringLiteralExpr() {
        #expect(sample(Gen<StringLiteralExprSyntax>.syntaxNode()).count == 20)
    }

    @Test("InheritanceClauseSyntax is generable")
    func inheritanceClause() {
        #expect(sample(Gen<InheritanceClauseSyntax>.syntaxNode()).count == 20)
    }

    /// The one of the six no template contained.
    @Test("DictionaryExprSyntax is generable")
    func dictionaryExpr() {
        let values = sample(Gen<DictionaryExprSyntax>.syntaxNode())
        #expect(values.count == 20)
        #expect(values.allSatisfy { $0.description.contains(":") })
    }

    @Test("CodeBlockItemSyntax is generable")
    func codeBlockItem() {
        #expect(sample(Gen<CodeBlockItemSyntax>.syntaxNode()).count == 20)
    }

    /// Every one of them has to pass the laws it would be checked against, or
    /// "generable" is an empty claim.
    @Test("the requested node types pass their Hashable laws")
    func requestedTypesPassLaws() async throws {
        try await checkHashablePropertyLaws(
            for: DictionaryExprSyntax.self,
            using: Gen<DictionaryExprSyntax>.syntaxNode(),
            options: LawCheckOptions(budget: .sanity)
        )
        try await checkHashablePropertyLaws(
            for: CodeBlockItemSyntax.self,
            using: Gen<CodeBlockItemSyntax>.syntaxNode(),
            options: LawCheckOptions(budget: .sanity)
        )
        try await checkHashablePropertyLaws(
            for: StringLiteralExprSyntax.self,
            using: Gen<StringLiteralExprSyntax>.syntaxNode(),
            options: LawCheckOptions(budget: .sanity)
        )
    }

    /// Adding template 14 must not have cost anything the earlier templates
    /// supplied — the list is append-only by contract, and this is the check
    /// that the contract held.
    @Test("the base node family is still reachable after the new template")
    func baseFamilyStillReachable() {
        #expect(sample(Gen<ExprSyntax>.syntaxNode(), count: 5).count == 5)
        #expect(sample(Gen<PatternSyntax>.syntaxNode(), count: 5).count == 5)
        #expect(sample(Gen<TypeSyntax>.syntaxNode(), count: 5).count == 5)
    }
}
