import Testing
import PropertyBased
@testable import PropertyLawKit

struct BudgetTests {

    @Test func sanityRuns100Trials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 100)
        }
    }

    @Test func standardRuns1000Trials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .standard)
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 1_000)
        }
    }

    @Test func customRunsRequestedTrials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .custom(trials: 250))
        )
        let nonViolations = results.filter { !$0.isViolation }
        try #require(nonViolations.isEmpty == false)
        for result in nonViolations {
            #expect(result.trials == 250)
        }
    }

    @Test func thoroughRuns10000Trials() async throws {
        // Not run through a law: 10 000 trials x several laws is real time, and
        // the tier's whole content is its count.
        #expect(TrialBudget.thorough.trialCount == 10_000)
    }

    /// **The tiers are effort, not coverage.** Every case reports a draw count
    /// and none reports an input space — which is the distinction the old
    /// `exhaustive` spelling blurred, and the reason `SpaceCoverage` exists
    /// separately.
    @Test func everyBudgetIsATrialCountAndNothingElse() {
        let counts: [TrialBudget: Int] = [
            .sanity: 100,
            .standard: 1_000,
            .thorough: 10_000,
            .custom(trials: 7): 7
        ]
        for (budget, expected) in counts {
            #expect(budget.trialCount == expected)
        }
    }

    /// The deprecated spelling still compiles and still means what it always
    /// meant — a trial count — so existing call sites keep working while the
    /// warning points them at the honest name.
    @available(*, deprecated, message: "exercises the deprecated shim on purpose")
    @Test func theDeprecatedExhaustiveSpellingStillResolvesToACount() {
        #expect(TrialBudget.exhaustive().trialCount == 10_000)
        #expect(TrialBudget.exhaustive(500).trialCount == 500)
        #expect(TrialBudget.exhaustive(500) == .custom(trials: 500),
                "the old spelling was always .custom under another name")
    }
    // MARK: - A budget below one trial checks nothing

    /// The failure a law check reports for this budget, or `nil` if it did not fail.
    private func refusal(for budget: TrialBudget) async -> CheckResult? {
        do {
            _ = try await checkEquatablePropertyLaws(
                for: Int.self,
                using: TestGen.smallInt(),
                options: LawCheckOptions(budget: budget, enforcement: .strict)
            )
        } catch let violation as PropertyLawViolation {
            return violation.results.first
        } catch {}
        return nil
    }

    /// `.custom(trials: 0)` used to run nothing and report a pass: a green result that checked
    /// nothing, which is the exact thing the kit's coverage reporting exists to prevent.
    @Test func aZeroBudgetFailsRatherThanPassingEmpty() async throws {
        let result = try #require(await refusal(for: .custom(trials: 0)))
        #expect(result.trials == 0)
        guard case .failed(let reason) = result.outcome else {
            Issue.record("expected a failed outcome, got \(result.outcome)")
            return
        }
        #expect(reason.contains("0 trials"), "the refusal must name the budget it refused: \(reason)")
    }

    /// A negative count used to crash the backend's `for _ in 0..<trials` with a range error — found
    /// by a `measure-non-negativity` law SwiftInferProperties proposed for `trialCount`.
    @Test func aNegativeBudgetFailsRatherThanTrapping() async throws {
        let result = try #require(await refusal(for: .custom(trials: -3)))
        guard case .failed(let reason) = result.outcome else {
            Issue.record("expected a failed outcome, got \(result.outcome)")
            return
        }
        #expect(reason.contains("-3 trials"))
    }

    /// Called directly, the backend reports zero trials run instead of trapping.
    @Test func theBackendToleratesANegativeCount() async {
        let result = await SwiftPropertyBasedBackend().check(
            trials: -1,
            seed: nil,
            sample: { rng in Int.random(in: 0 ... 9, using: &rng) },
            property: { _ in true }
        )
        guard case .passed(let trialsRun, _) = result else {
            Issue.record("expected an empty pass, got \(result)")
            return
        }
        #expect(trialsRun == 0)
    }
}
