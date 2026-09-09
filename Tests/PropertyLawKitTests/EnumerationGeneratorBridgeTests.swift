import PropertyBased
import Testing
@testable import PropertyLawKit

/// The bridge from a bounded space to an ordinary `Generator`.
///
/// Its doc comment makes two concessions — no shrinking, no coverage
/// denominator — and one claim: structural reach survives sampling. All three
/// are asserted here, because a concession that drifts from the code is worse
/// than no concession at all.
struct EnumerationGeneratorBridgeTests {

    @Test func theBridgeDrawsOnlyCasesFromTheSpace() {
        let space = Every.subsets("subset", of: 6)
        let legal = Set(space.indices.map { space[$0] })
        var rng = Xoshiro(seed: (7, 8, 9, 10))
        for _ in 0 ..< 500 {
            #expect(legal.contains(space.generator.run(using: &rng)))
        }
    }

    @Test func theBridgeReachesMostOfASmallSpace() {
        let space = Every.subsets("subset", of: 6)
        var rng = Xoshiro(seed: (7, 8, 9, 10))
        var seen = Set<[Int]>()
        for _ in 0 ..< 1000 { seen.insert(space.generator.run(using: &rng)) }
        #expect(seen.count == space.count, "1 000 draws should cover a 64-case space")
    }

    /// **Concession one, pinned.** `LawCheck.shrink` is value-level and the kit
    /// never threads a `Generator` through a driver, so the index shrinker in
    /// the bridge's type is not consulted. If that ever changes, this test
    /// fails and the doc comment needs rewriting.
    @Test func theBridgeDoesNotShrink() async {
        let space = Every.subsets("subset", of: 10)
        let result = await runUnaryLaw(
            "Spike.cardinalityUnderThree",
            source: .sampling(space.generator),
            options: LawCheckOptions(budget: .standard),
            property: { (subset: [Int]) in subset.count < 3 },
            formatCounterexample: { subset, _ in "\(subset)" }
        )
        #expect(result.isViolation)
        #expect(result.shrinkSteps == 0, "the bridge advertises no shrinking")
    }

    /// **Concession two, pinned.** A sampled run cannot say what fraction of the
    /// space it saw, and reports `nil` like every other sampled law — as opposed
    /// to the same space walked, which reports its denominator.
    @Test func theBridgeReportsNoCoverageButAWalkDoes() async throws {
        let space = Every.subsets("subset", of: 6)
        let sampled = try await checkEquatablePropertyLaws(
            using: space.generator,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(sampled.allSatisfy { $0.coverage == nil })

        let walked = try await checkEveryCase(
            of: space,
            law: "Spike.alwaysHolds",
            satisfies: { _ in true }
        )
        #expect(walked.first?.coverage?.spaceSize == 64)
    }

    /// **The claim, pinned.** Sampling a space still reaches cases a
    /// construction-path generator cannot produce at all — that property belongs
    /// to the space, not to the traversal, which is why the bridge is worth
    /// having despite the two concessions above.
    @Test func structuralReachSurvivesSampling() {
        // Subsets of 0..<8 that a "build a set by inserting k random elements
        // drawn from 0..<4" generator can never produce: anything containing an
        // element above 3.
        let space = Every.subsets("subset", of: 8)
        var rng = Xoshiro(seed: (11, 12, 13, 14))
        var reachedBeyondFour = false
        for _ in 0 ..< 200 where space.generator.run(using: &rng).contains(where: { $0 >= 4 }) {
            reachedBeyondFour = true
        }
        #expect(reachedBeyondFour, "the space's own definition is what puts those cases in reach")
    }
}
