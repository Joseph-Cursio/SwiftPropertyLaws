import Testing
@testable import PropertyLawKit

/// What a walk's result *says*. `SpaceCoverage` exists so a result can stop
/// implying coverage it does not have, which only pays off if the rendered
/// output actually carries it — and if a sampled result is left alone.
struct EnumerationReportingTests {

    private func result(coverage: SpaceCoverage?, outcome: CheckResult.Outcome, trials: Int) -> CheckResult {
        CheckResult(
            protocolLaw: "Spike.law",
            tier: .strict,
            trials: trials,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: Environment.current(backend: SwiftPropertyBasedBackend()),
            outcome: outcome,
            coverage: coverage
        )
    }

    @Test func aCompleteWalkSaysSoAndOffersNoSeed() {
        let text = ViolationFormatter.format(
            result(coverage: SpaceCoverage(casesRun: 64, spaceSize: 64), outcome: .passed, trials: 64)
        )
        #expect(text.contains("walked all 64 cases"))
        #expect(text.contains("Deterministic walk"))
        #expect(!text.contains("Replay with seed"), "a walk consumes no randomness; a seed would be noise")
    }

    @Test func aTruncatedWalkReportsTheShortfall() {
        let text = ViolationFormatter.format(
            result(coverage: SpaceCoverage(casesRun: 100, spaceSize: 1024), outcome: .passed, trials: 100)
        )
        #expect(text.contains("walked 100 of 1024 cases"))
        #expect(!text.contains("walked all"))
    }

    /// A failing walk stopped because it found something, not because it ran
    /// out — so it must not read as 57/1024 coverage.
    @Test func aFailingWalkReportsWhereItStoppedNotHowMuchItCovered() {
        let text = ViolationFormatter.format(
            result(
                coverage: SpaceCoverage(casesRun: 57, spaceSize: 1024),
                outcome: .failed(counterexample: "subset=[0, 1, 2]"),
                trials: 57
            )
        )
        #expect(text.contains("failed at case 57 of 1024"))
        #expect(text.contains("Counterexample: subset=[0, 1, 2]"))
        #expect(!text.contains("walked"))
    }

    /// The nil-versus-empty discipline: a sampled law does not know its input
    /// space, and its output must be exactly what it was before this shipped.
    @Test func aSampledResultIsUnchanged() {
        let text = ViolationFormatter.format(result(coverage: nil, outcome: .passed, trials: 1000))
        #expect(text.contains("1000 trials"))
        #expect(text.contains("Replay with seed:"))
        #expect(!text.contains("cases"))
        #expect(!text.contains("Deterministic walk"))
    }

    @Test func coverageIsCompleteOnlyWhenEveryCaseWasSeen() {
        #expect(SpaceCoverage(casesRun: 64, spaceSize: 64).isComplete)
        #expect(SpaceCoverage(casesRun: 63, spaceSize: 64).isComplete == false)
        #expect(SpaceCoverage(casesRun: 0, spaceSize: 0).isComplete, "an empty space is trivially covered")
    }

    /// An empty space is a legal space, and walking it proves nothing rather
    /// than failing.
    @Test func anEmptySpaceWalksCleanlyAndSaysItCoveredEverything() async throws {
        let results = try await checkEveryCase(
            of: Every.elements("nothing", in: [Int]()),
            law: "Spike.neverApplies",
            satisfies: { _ in false }
        )
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.casesRun == 0)
        #expect(coverage.spaceSize == 0)
        #expect(results.first?.isViolation == false)
    }
}
