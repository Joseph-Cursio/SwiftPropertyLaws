@testable import PropertyLawKit
import Testing

/// Sampling a space while keeping the index — the middle ground between walking
/// it and handing it to `Enumeration.generator`.
///
/// The two things this recovers are exactly the two the bridge gives up, so both
/// are measured here against the bridge rather than asserted.
@Suite("Sampled spaces")
struct SampledSpaceTests {

    /// **Minimality, against the bridge, on the same space and law.** The bridge
    /// reports whatever came up first; this reports the smallest case that
    /// exists, because the index shrinks toward zero and the space is ordered.
    ///
    /// **The seed is fixed.** 968 of the 1,024 subsets fail, so about one run
    /// in a thousand drew the minimal witness first, had nothing to shrink,
    /// and failed `shrinkSteps > 0` while reporting the right counterexample.
    /// It happened once in a full run on 2026-11-11. Under this seed the first
    /// failing draw is not the witness, which `shrunkFrom` confirms below.
    @Test func samplingKeepsMinimalityWhereTheBridgeLosesIt() async {
        let space = Every.subsets("subset", of: 10)
        let options = LawCheckOptions(budget: .standard, seed: RareAntecedentTests.mixedSeed(1))

        let bridged = await runUnaryLaw(
            "Spike.cardinalityUnderThree",
            source: .sampling(space.generator),
            options: options,
            property: { (subset: [Int]) in subset.count < 3 },
            formatCounterexample: { subset, _ in "\(subset)" }
        )
        let sampled = await runUnaryLaw(
            "Spike.cardinalityUnderThree",
            source: .sampledFromSpace(space),
            options: options,
            property: { (subset: [Int]) in subset.count < 3 },
            formatCounterexample: { subset, _ in "\(subset)" }
        )

        #expect(bridged.isViolation)
        #expect(sampled.isViolation)
        #expect(bridged.shrinkSteps == 0, "the bridge advertises no shrinking")
        #expect(sampled.shrinkSteps > 0)
        #expect(sampled.shrunkFrom != nil && sampled.shrunkFrom != sampled.counterexample)
        // The minimal witness of "cardinality >= 3" is the first 3-element
        // subset, at index 56 of the cardinality-ascending space.
        #expect(sampled.counterexample == "subset=[0, 1, 2] — [0, 1, 2]",
                "got \(sampled.counterexample ?? "nil")")
    }

    /// **The last step to index 0.** Halving ends on `index - 1` for any index
    /// of 2 or more, so the explicit `index - 1` candidate matters only at 1.
    /// The witness above sits at 56 and never needs it. A law that fails
    /// everywhere has its minimal case at index 0, and dropping that candidate
    /// left the shrink stuck at 1.
    @Test func aFailureEverywhereShrinksToTheFirstCase() async {
        let failure = await runUnaryLaw(
            "Spike.neverHolds",
            source: .sampledFromSpace(Every.elements("value", in: Array(0 ..< 64))),
            options: LawCheckOptions(budget: .sanity),
            property: { (_: Int) in false },
            formatCounterexample: { value, _ in "\(value)" }
        )
        #expect(failure.counterexample == "value=0 — 0", "got \(failure.counterexample ?? "nil")")
    }

    /// **A denominator, which no other sampled path in the kit reports.**
    @Test func samplingReportsDistinctCoverageWhereTheBridgeReportsNone() async throws {
        let space = Every.subsets("subset", of: 6)

        let bridged = try await checkEquatablePropertyLaws(
            using: space.generator,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(bridged.allSatisfy { $0.coverage == nil })

        let sampled = try await checkSampledCases(
            of: space,
            law: "Spike.alwaysHolds",
            options: LawCheckOptions(budget: .standard)
        ) { _ in true }
        let coverage = try #require(sampled.first?.coverage)
        #expect(coverage.spaceSize == 64)
        #expect(coverage.casesRun == 64, "1 000 draws should reach all 64 cases")
        #expect(coverage.isComplete)
    }

    /// **Why the count is deduplicated**, tested where draws and distinct cases
    /// actually diverge.
    ///
    /// An earlier version of this test drew 50 times from a 1 024-case space and
    /// asserted `casesRun <= 50`. Both counting rules satisfy that — 50 draws
    /// into a large space almost never collide — so the assertion was shaped
    /// like a check without discriminating, and a mutant that counted draws
    /// survived it. **Over-sampling a small space is the only arrangement where
    /// the two rules give different answers**, so that is what this draws: 500
    /// times from 16 cases, where draw-counting would report 500.
    @Test func coverageCountsDistinctCasesNotDraws() async throws {
        let space = Every.subsets("subset", of: 4)
        #expect(space.count == 16)
        let results = try await checkSampledCases(
            of: space,
            law: "Spike.alwaysHolds",
            options: LawCheckOptions(budget: .custom(trials: 500))
        ) { _ in true }
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.spaceSize == 16)
        #expect(coverage.casesRun <= 16,
                "500 draws from 16 cases cannot cover more than 16 — a count of draws would say 500")
        #expect(coverage.casesRun == 16, "500 draws should reach all 16")
    }

    /// The companion: a space large enough that 50 draws cannot exhaust it, so
    /// the run reports incomplete coverage rather than rounding up to it.
    @Test func aSmallSampleOfALargeSpaceReportsIncompleteCoverage() async throws {
        let results = try await checkSampledCases(
            of: Every.subsets("subset", of: 10),
            law: "Spike.alwaysHolds",
            options: LawCheckOptions(budget: .custom(trials: 50))
        ) { _ in true }
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.spaceSize == 1_024)
        #expect(coverage.casesRun <= 50)
        #expect(coverage.isComplete == false)
    }

    /// A partial walk and a sample of the same size are different traversals of
    /// the same space, and both say so honestly.
    @Test func aPrefixWalkAndASampleDifferButBothReportTruthfully() async throws {
        let space = Every.subsets("subset", of: 8)
        let walked = try await checkEveryCase(
            of: space.prefix(40),
            law: "Spike.alwaysHolds"
        ) { _ in true }
        let sampled = try await checkSampledCases(
            of: space,
            law: "Spike.alwaysHolds",
            options: LawCheckOptions(budget: .custom(trials: 40))
        ) { _ in true }
        #expect(walked.first?.coverage?.spaceSize == 256)
        #expect(sampled.first?.coverage?.spaceSize == 256)
        #expect(walked.first?.coverage?.casesRun == 40, "a prefix walk sees exactly its first 40")
        #expect(sampled.first?.coverage?.isComplete == false)
    }
}
