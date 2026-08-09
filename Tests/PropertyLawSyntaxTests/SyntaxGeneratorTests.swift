import PropertyBased
import PropertyLawKit
import SwiftSyntax
import Testing
@testable import PropertyLawSyntax

/// `Syntax` identity is **allocation-scoped**, and this suite exists because
/// two plausible designs failed before that was measured.
///
/// - A **32-node pool** capped unique hashes and failed `Hashable.distribution`
///   at 1 000 trials (ratio 0.032, threshold 0.10) — a Heuristic violation
///   against correct code.
/// - **Parsing a fresh tree per draw** looked like the fix and was worse: a
///   node's id is tied to its tree's arena, which is freed and reused the moment
///   the tree is dropped. 300 parsed-and-dropped trees gave **78** unique ids;
///   the generator gave 751 in 10 000 draws, ratio 0.075 — failing the same law
///   the pool was rejected for.
/// - **A large pool whose trees stay alive** gives one identity per node: 300
///   retained trees gave 11 700 unique ids from 11 700 nodes.
///
/// So the pool was right and the reason for rejecting it was wrong — sizing is
/// the whole game. `distributionStaysHealthy` runs to the largest budget the kit
/// ships, because every earlier version of this suite passed at small budgets
/// while the design was broken at large ones.
struct SyntaxGeneratorTests {

    private func sample(
        _ generator: Generator<Syntax, some SendableSequenceType>,
        count: Int,
        seed: UInt64 = 1
    ) -> [Syntax] {
        var rng = Xoshiro(seed: (seed, seed &+ 1, seed &+ 2, seed &+ 3))
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    private func equalPairs(in values: [Syntax]) -> Int {
        var count = 0
        for index in stride(from: 0, to: values.count - 1, by: 2)
        where values[index] == values[index + 1] {
            count += 1
        }
        return count
    }

    // MARK: - The default generator

    /// The load-bearing guard, and it must run to **10 000** — the
    /// `.exhaustive` budget. Both broken designs passed this at 1 000 and failed
    /// at 10 000, so a small-budget check is exactly the test that would not
    /// have caught either. Drawing from a prebuilt pool is cheap, so the large
    /// case costs nothing now.
    @Test("the default generator keeps hash distribution healthy", arguments: [100, 1000, 10000])
    func distributionStaysHealthy(_ trials: Int) {
        let values = sample(Gen<Syntax>.syntax(), count: trials)
        let ratio = Double(Set(values.map(\.hashValue)).count) / Double(trials)
        #expect(ratio > 0.10, "ratio \(ratio) at \(trials) trials would trip Hashable.distribution")
    }

    /// **Retention is the mechanism, and a ratio alone would not pin it.** Every
    /// node in the pool must carry its own identity; if the trees were dropped
    /// the ids would collide and this collapses.
    @Test("every node in the pool has a distinct identity")
    func poolIdentitiesAreDistinct() {
        let nodes = SyntaxNodePool.allNodes
        #expect(nodes.count > 1000, "pool too small for the largest budget: \(nodes.count)")
        #expect(Set(nodes.map(\.id)).count == nodes.count,
                "only \(Set(nodes.map(\.id)).count) identities across \(nodes.count) nodes")
    }

    /// The pool's trees differ in **shape**, not merely in tokens — identity
    /// keys on structural position, so same-shaped trees would contribute far
    /// fewer identities than they do nodes.
    @Test("the pool spans many distinct tree shapes")
    func poolSpansTreeShapes() {
        let roots = Set(SyntaxNodePool.allNodes.map(\.root.description))
        #expect(roots.count > Gen<Syntax>.syntaxSourceTemplates.count * 2,
                "only \(roots.count) distinct trees in the pool")
    }

    /// The trade, stated as a measurement: draws are *almost* always distinct,
    /// at the `1 / poolSize` rate a pool implies. Not zero — the mechanism
    /// exists — but far too rare for the Equatable antecedent to be exercised,
    /// which is what `pooled(size:)` is for.
    @Test("equal pairs are rare at the default pool size")
    func equalPairsAreRareByDefault() {
        let pairs = equalPairs(in: sample(Gen<Syntax>.syntax(), count: 2000))
        #expect(pairs < 20, "got \(pairs)/1000 equal pairs — the pool is far too small")
    }

    @Test("the default generator spans many node kinds")
    func defaultSpansNodeKinds() {
        let kinds = Set(sample(Gen<Syntax>.syntax(), count: 500).map(\.kind))
        #expect(kinds.count >= 15, "expected a spread of node kinds; got \(kinds.count)")
    }

    /// Every template has to parse into something, or a draw that lands on it
    /// silently degrades the variety the list was chosen for.
    @Test("every template parses to a non-trivial tree")
    func everyTemplateParses() {
        for index in Gen<Syntax>.syntaxSourceTemplates.indices {
            let node = SyntaxNodePool.node(template: index, discriminator: 7, nodeIndex: 0)
            #expect(node.children(viewMode: .sourceAccurate).isEmpty == false,
                    "template \(index) parsed to a leaf")
        }
    }

    /// `nodeIndex` is taken modulo the tree's node count, so no draw can be out
    /// of range however the templates change.
    @Test("an out-of-range node index wraps instead of trapping")
    func nodeIndexWraps() {
        // Template 0 parses to far fewer than 4 095 nodes. Not trapping is half
        // the assertion; the other half is that the wrapped index still lands in
        // the tree it was supposed to — an empty collection node has an empty
        // `description`, so the node itself is a poor witness, but its root is a
        // good one.
        let node = SyntaxNodePool.node(template: 0, discriminator: 1, nodeIndex: 4095)
        // Compared against the source builder rather than a literal, so the
        // test does not re-pin the template text every time the pool changes.
        #expect(node.root.description
            == SyntaxNodePool.source(template: 0, discriminator: 1))
    }

    /// The template index wraps too, so a caller passing a stale index (or the
    /// list shrinking) can't trap.
    @Test("an out-of-range template index wraps")
    func templateIndexWraps() {
        let count = Gen<Syntax>.syntaxSourceTemplates.count
        let wrapped = SyntaxNodePool.node(template: count, discriminator: 3, nodeIndex: 0)
        #expect(wrapped.root.description
            == SyntaxNodePool.source(template: 0, discriminator: 3))
    }

    // MARK: - The pooled generator and its cost

    @Test("the pooled generator produces equal pairs at roughly 1/size")
    func pooledProducesEqualPairs() {
        let pairs = equalPairs(in: sample(Gen<Syntax>.pooled(size: 32), count: 2000))
        // 1 000 pairs at p = 1/32 → expect ~31.
        #expect(pairs > 5, "equal pairs never occurred — the pooled mode has no purpose")
        #expect(pairs < 300, "values are barely distinct — got \(pairs)/1000")
    }

    /// The documented cost, pinned. A doc comment claiming this would rot; a
    /// test fails when it stops being true.
    @Test("the pooled generator trips the distribution threshold")
    func pooledTripsDistribution() {
        let values = sample(Gen<Syntax>.pooled(size: 32), count: 1000)
        let ratio = Double(Set(values.map(\.hashValue)).count) / Double(1000)
        #expect(ratio < 0.10, "ratio \(ratio) — the documented pooled/distribution conflict is gone")
    }

    @Test("the pool honours its size")
    func poolSizeIsHonoured() {
        #expect(SyntaxNodePool.pool(size: 32).count == 32)
        #expect(SyntaxNodePool.pool(size: 1).count == 1)
    }

    /// Taking a prefix would draw every node from the first template or two —
    /// the flattened order is depth-first — so the pool would be a few node
    /// kinds from one shape.
    @Test("the pool is strided across templates, not a prefix")
    func poolIsStrided() {
        let pool = SyntaxNodePool.pool(size: 32)
        #expect(pool != Array(SyntaxNodePool.allNodes.prefix(32)))
        #expect(Set(pool.map(\.kind)).count >= 8)
    }

    /// Degenerate but valid, and the only case where every pair is equal.
    @Test("a single-node pool yields one value")
    func degenerateSinglePool() {
        #expect(Set(sample(Gen<Syntax>.pooled(size: 1), count: 20).map(\.id)).count == 1)
    }

    // MARK: - Determinism

    /// What the generator actually guarantees: a replayed seed reproduces the
    /// same nodes, and therefore the same equal/unequal relationships.
    /// `SyntaxIdentifier` raw values are not meaningful across processes, so the
    /// relationships are the part worth pinning.
    @Test("the same seed replays the same draws")
    func seededReplay() {
        let first = sample(Gen<Syntax>.syntax(), count: 50)
        let second = sample(Gen<Syntax>.syntax(), count: 50)
        #expect(first.map(\.description) == second.map(\.description))
    }

    @Test("different seeds differ")
    func differentSeedsDiffer() {
        let first = sample(Gen<Syntax>.syntax(), count: 50, seed: 1)
        let second = sample(Gen<Syntax>.syntax(), count: 50, seed: 99)
        #expect(first.map(\.description) != second.map(\.description))
    }

    @Test("the pool is stable across rebuilds")
    func poolIsStable() {
        #expect(SyntaxNodePool.pool(size: 32).map(\.id)
            == SyntaxNodePool.pool(size: 32).map(\.id))
    }

    // MARK: - The laws it exists to run

    /// The point of the exercise: the suite the discovery plugin emits for
    /// `Syntax` now has a generator and runs clean — no Heuristic false alarm.
    @Test("Syntax passes the Hashable law suite")
    func syntaxPassesHashableLaws() async throws {
        try await checkHashablePropertyLaws(
            for: Syntax.self,
            using: Gen<Syntax>.syntax(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test("Syntax passes the Identifiable law suite")
    func syntaxPassesIdentifiableLaws() async throws {
        try await checkIdentifiablePropertyLaws(
            for: Syntax.self,
            using: Gen<Syntax>.syntax(),
            options: LawCheckOptions(budget: .sanity)
        )
    }
}
