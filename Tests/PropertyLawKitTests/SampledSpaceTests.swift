import Testing
@testable import PropertyLawKit

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
    @Test func samplingKeepsMinimalityWhereTheBridgeLosesIt() async {
        let space = Every.subsets("subset", of: 10)

        let bridged = await runUnaryLaw(
            "Spike.cardinalityUnderThree",
            source: .sampling(space.generator),
            options: LawCheckOptions(budget: .standard),
            property: { (subset: [Int]) in subset.count < 3 },
            formatCounterexample: { subset, _ in "\(subset)" }
        )
        let sampled = await runUnaryLaw(
            "Spike.cardinalityUnderThree",
            source: .sampledFromSpace(space),
            options: LawCheckOptions(budget: .standard),
            property: { (subset: [Int]) in subset.count < 3 },
            formatCounterexample: { subset, _ in "\(subset)" }
        )

        #expect(bridged.isViolation)
        #expect(sampled.isViolation)
        #expect(bridged.shrinkSteps == 0, "the bridge advertises no shrinking")
        #expect(sampled.shrinkSteps > 0)
        // The minimal witness of "cardinality >= 3" is the first 3-element
        // subset, at index 56 of the cardinality-ascending space.
        #expect(sampled.counterexample == "subset=[0, 1, 2] — [0, 1, 2]",
                "got \(sampled.counterexample ?? "nil")")
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
            options: LawCheckOptions(budget: .standard),
            satisfies: { _ in true }
        )
        let coverage = try #require(sampled.first?.coverage)
        #expect(coverage.spaceSize == 64)
        #expect(coverage.casesRun == 64, "1 000 draws should reach all 64 cases")
        #expect(coverage.isComplete)
    }

    /// **Why the count is deduplicated.** Counting draws would let 1 000 draws
    /// over a 64-case space report `casesRun: 1000`, and `isComplete` —
    /// `casesRun >= spaceSize` — would answer `true` for a run that missed
    /// cases. Distinct counting makes the number mean what it says.
    @Test func coverageCountsDistinctCasesNotDraws() async throws {
        let space = Every.subsets("subset", of: 10)
        let results = try await checkSampledCases(
            of: space,
            law: "Spike.alwaysHolds",
            options: LawCheckOptions(budget: .custom(trials: 50)),
            satisfies: { _ in true }
        )
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.spaceSize == 1024)
        #expect(coverage.casesRun <= 50, "50 draws cannot cover more than 50 cases")
        #expect(coverage.isComplete == false)
    }

    /// A partial walk and a sample of the same size are different traversals of
    /// the same space, and both say so honestly.
    @Test func aPrefixWalkAndASampleDifferButBothReportTruthfully() async throws {
        let space = Every.subsets("subset", of: 8)
        let walked = try await checkEveryCase(
            of: space.prefix(40),
            law: "Spike.alwaysHolds",
            satisfies: { _ in true }
        )
        let sampled = try await checkSampledCases(
            of: space,
            law: "Spike.alwaysHolds",
            options: LawCheckOptions(budget: .custom(trials: 40)),
            satisfies: { _ in true }
        )
        #expect(walked.first?.coverage?.spaceSize == 256)
        #expect(sampled.first?.coverage?.spaceSize == 256)
        #expect(walked.first?.coverage?.casesRun == 40, "a prefix walk sees exactly its first 40")
        #expect(sampled.first?.coverage?.isComplete == false)
    }
}
