import PropertyBased
import PropertyLawKit
import SwiftSyntax
import Testing
@testable import PropertyLawSyntax

/// `Gen<T>.syntaxNode()` covers every typed node in swift-syntax, not just the
/// three the corpus asked for — `ExprSyntax` (34 placeholder slots),
/// `TokenSyntax` (5) and the rest are the same parsed tree filtered by
/// `Syntax.as(T.self)`, so writing them by hand would have left
/// `FunctionDeclSyntax` and ~300 siblings still asking.
///
/// **`RawTokenSyntax` is out of scope on purpose** — it is `@_spi(RawSyntax)`
/// with an internal initializer, so shipping a generator would put an unstable
/// upstream interface in this package's public surface. There is no test for
/// its absence: a type this package cannot name is enforced by the compiler,
/// and writing an assertion that pretends otherwise would be worse than the
/// comment.
struct SyntaxNodeGeneratorTests {

    private func sample<T: SyntaxProtocol>(
        _ generator: Generator<T, some SendableSequenceType>,
        count: Int,
        seed: UInt64 = 1
    ) -> [T] {
        var rng = Xoshiro(seed: (seed, seed &+ 1, seed &+ 2, seed &+ 3))
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    // MARK: - Every shipped node type is reachable

    /// The precondition in `typedNode` is unreachable for these types, and this
    /// is the proof. If a template list edit ever removes the last `PatternSyntax`,
    /// this fails instead of a downstream suite trapping mid-run.
    @Test("the base node family is reachable from the templates")
    func everyBaseNodeTypeIsReachable() {
        #expect(sample(Gen<ExprSyntax>.syntaxNode(), count: 20).count == 20)
        #expect(sample(Gen<TokenSyntax>.syntaxNode(), count: 20).count == 20)
        #expect(sample(Gen<DeclSyntax>.syntaxNode(), count: 20).count == 20)
        #expect(sample(Gen<StmtSyntax>.syntaxNode(), count: 20).count == 20)
        #expect(sample(Gen<PatternSyntax>.syntaxNode(), count: 20).count == 20)
        #expect(sample(Gen<TypeSyntax>.syntaxNode(), count: 20).count == 20)
    }

    /// Concrete node types work too, which is the point of being generic — the
    /// plugin asks for whatever the scanned code mentions.
    @Test("concrete node types are reachable")
    func concreteNodeTypesReachable() {
        #expect(sample(Gen<FunctionDeclSyntax>.syntaxNode(), count: 5).count == 5)
        #expect(sample(Gen<CodeBlockItemListSyntax>.syntaxNode(), count: 5).count == 5)
    }

    /// **The rotation is now a fallback rather than the main path**, and the
    /// test says so rather than pretending otherwise. Each pool tree is a run of
    /// up to `statementCountRange.upperBound` statements drawn from across the
    /// template list, so most trees already contain most node kinds — the
    /// rotation only matters for a kind that a particular run happens to miss.
    ///
    /// What must stay true is the outcome: a requested type is found, and it
    /// comes from a tree the requested template leads.
    /// The per-draw rotation is gone: a typed generator filters the whole
    /// retained pool once, so a type present in *any* tree is reachable from
    /// every draw. That is strictly stronger than rotating from one tree to the
    /// next, and it is what removes the per-draw parse.
    @Test("a typed pool spans every tree that contains the type")
    func typedPoolSpansAllTrees() {
        let functions = SyntaxNodePool.typedPool(FunctionDeclSyntax.self)
        let roots = Set(functions.map { Syntax($0).root.description })
        #expect(roots.count > 1, "the typed pool came from a single tree")
        #expect(Set(functions.map(\.id)).count == functions.count,
                "typed pool has colliding identities — the trees are not retained")
    }

    /// Every returned value really is of the requested type — a generator that
    /// quietly substituted a parent node would still typecheck at the call site.
    @Test("drawn nodes are of the requested kind")
    func drawnNodesHaveTheRightKind() {
        for expr in sample(Gen<ExprSyntax>.syntaxNode(), count: 50) {
            #expect(Syntax(expr).is(ExprSyntax.self))
        }
        for token in sample(Gen<TokenSyntax>.syntaxNode(), count: 50) {
            #expect(Syntax(token).is(TokenSyntax.self))
        }
    }

    // MARK: - The same distribution guarantee

    /// The constraint that decided `Gen<Syntax>.syntax()` applies identically
    /// here: a fixed pool would cap unique hashes and trip
    /// `Hashable.distribution` against correct code.
    @Test("typed generators keep hash distribution healthy", arguments: [100, 1000])
    func distributionStaysHealthy(_ trials: Int) {
        let exprs = sample(Gen<ExprSyntax>.syntaxNode(), count: trials)
        let ratio = Double(Set(exprs.map(\.hashValue)).count) / Double(trials)
        #expect(ratio > 0.10, "ratio \(ratio) at \(trials) trials would trip the law")
    }

    /// Same gap as on `Gen<Syntax>.syntax()`: the ratio test passes even with a
    /// constant discriminator, because the templates alone supply enough
    /// distinct nodes at these budgets. Pin the mechanism directly.
    @Test("the discriminator varies the parsed tree for typed nodes")
    func discriminatorVariesTheTree() {
        let roots = Set(sample(Gen<ExprSyntax>.syntaxNode(), count: 200)
            .map(\.root.description))
        #expect(roots.count > Gen<Syntax>.syntaxSourceTemplates.count,
                "only \(roots.count) distinct trees — the discriminator is not reaching the source")
    }

    @Test("typed generators span several node kinds")
    func spansKinds() {
        let kinds = Set(sample(Gen<ExprSyntax>.syntaxNode(), count: 300).map(\.kind))
        #expect(kinds.count >= 4, "expected a spread of expression kinds; got \(kinds.count)")
    }

    // MARK: - Determinism

    @Test("the same seed replays the same draws")
    func seededReplay() {
        let first = sample(Gen<ExprSyntax>.syntaxNode(), count: 40)
        let second = sample(Gen<ExprSyntax>.syntaxNode(), count: 40)
        #expect(first.map(\.description) == second.map(\.description))
    }

    @Test("different seeds differ")
    func differentSeedsDiffer() {
        let first = sample(Gen<TokenSyntax>.syntaxNode(), count: 40, seed: 1)
        let second = sample(Gen<TokenSyntax>.syntaxNode(), count: 40, seed: 99)
        #expect(first.map(\.description) != second.map(\.description))
    }

    // MARK: - The laws

    @Test("ExprSyntax passes the Hashable law suite")
    func exprPassesHashableLaws() async throws {
        try await checkHashablePropertyLaws(
            for: ExprSyntax.self,
            using: Gen<ExprSyntax>.syntaxNode(),
            // `.standard` here as the realistic-budget proof; the sibling
            // suites below use `.sanity` because they are showing the suite
            // *runs clean*, not re-measuring distribution — parsing per draw
            // makes a 1 000-trial suite the dominant cost in this target.
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test("TokenSyntax passes the Hashable law suite")
    func tokenPassesHashableLaws() async throws {
        try await checkHashablePropertyLaws(
            for: TokenSyntax.self,
            using: Gen<TokenSyntax>.syntaxNode(),
            options: LawCheckOptions(budget: .sanity)
        )
    }

    @Test("DeclSyntax passes the Hashable law suite")
    func declPassesHashableLaws() async throws {
        try await checkHashablePropertyLaws(
            for: DeclSyntax.self,
            using: Gen<DeclSyntax>.syntaxNode(),
            options: LawCheckOptions(budget: .sanity)
        )
    }
}
