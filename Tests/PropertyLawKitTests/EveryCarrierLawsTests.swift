import PropertyBased
@testable import PropertyLawKit
import Testing

/// Running a whole suite once per carrier. The other entries vary a law's
/// inputs; this one varies its subject.
@Suite("Laws over every carrier")
struct EveryCarrierLawsTests {

    /// A `Collection` whose `count` is correct at every length but one. The
    /// defect is a property of the *carrier*, not of any input drawn from it —
    /// which is exactly the class no amount of input sampling reaches, because
    /// the suite is only ever pointed at one carrier.
    private struct LyingCount: Collection, Sendable, CustomStringConvertible {
        let elements: [Int]
        var startIndex: Int { 0 }
        var endIndex: Int { elements.count }

        func index(after position: Int) -> Int { position + 1 }
        subscript(position: Int) -> Int { elements[position] }
        /// Correct everywhere except length 7.
        var count: Int { elements.count == 7 ? 6 : elements.count }
        var description: String { "count \(elements.count)" }
    }

    private func lengths(upTo bound: Int) -> Enumeration<LyingCount> {
        Every.elements(
            "length",
            in: (0 ... bound).map { LyingCount(elements: Array(0 ..< $0)) }
        ) { $0.elements.count }
    }

    private func honestCarriers() -> Enumeration<[Int]> {
        Every.elements("array", in: (0 ... 6).map { Array(0 ..< $0) }) { $0.count }
    }

    // MARK: - Shape

    @Test("results are merged one per law, not one per carrier")
    func resultsAreMergedPerLaw() async throws {
        let results = try await checkEveryCarrier(of: honestCarriers()) { carrier, options in
            try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
        }
        #expect(results.count == Set(results.map(\.protocolLaw)).count, "a law appears twice")
        #expect(results.count > 1)
        #expect(results.allSatisfy { !$0.isViolation })
    }

    /// Coverage here describes the **carrier** space — the walk this call
    /// performed — rather than any law's input space.
    @Test("coverage describes the carrier space")
    func coverageDescribesTheCarrierSpace() async throws {
        let carriers = honestCarriers()
        let results = try await checkEveryCarrier(of: carriers) { carrier, options in
            try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
        }
        #expect(carriers.count == 7)
        #expect(results.allSatisfy { $0.coverage?.spaceSize == 7 })
        #expect(results.allSatisfy { $0.coverage?.casesRun == 7 })
        #expect(results.allSatisfy { $0.coverage?.isComplete == true })
    }

    /// `options.budget` is ignored and `perCarrier` decides, because the naive
    /// composition multiplies: carriers × trials × laws.
    @Test("the per-carrier budget decides, and trials accumulate across carriers")
    func perCarrierBudgetIsWhatCounts() async throws {
        let results = try await checkEveryCarrier(
            of: honestCarriers(),
            options: LawCheckOptions(budget: .thorough),
            perCarrier: .custom(trials: 5)
        ) { carrier, options in
            try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
        }
        // 7 carriers x 5 trials, not 7 x 10 000 and not 10 000.
        let perLawTrials = Set(results.map(\.trials))
        #expect(perLawTrials == [35], "got \(perLawTrials.sorted())")
    }

    // MARK: - The payoff

    /// **The defect a single carrier cannot show.** `LyingCount` misreports its
    /// count at exactly one length, so pointing the suite at one carrier finds
    /// it only if that carrier happens to be the seventh — 1 chance in 11 — and
    /// no trial budget improves those odds, because the budget varies inputs and
    /// the defect is in the subject.
    @Test("a carrier-dependent defect is found, at the smallest carrier showing it")
    func carrierEnumerationFindsWhatOneCarrierCannot() async {
        var reported: CheckResult?
        do {
            _ = try await checkEveryCarrier(of: lengths(upTo: 10)) { carrier, options in
                try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
            }
        } catch let violation as PropertyLawViolation {
            reported = violation.results.first(where: \.isViolation)
        } catch {
            Issue.record(error)
        }
        let result = try? #require(reported)
        #expect(result?.isViolation == true)
        // Carriers are walked smallest first, so the reported one is the
        // shortest collection that misreports — length 7, not 8, 9 or 10.
        #expect(result?.counterexample?.hasPrefix("length=count 7 — ") == true,
                "got \(result?.counterexample ?? "nil")")
        #expect(result?.coverage?.casesRun == 8, "the walk should stop at the eighth carrier")
        #expect(result?.coverage?.isComplete == false)
    }

    /// The test above fails at the eighth carrier, by which time every law was
    /// already recorded from an earlier one. A law fails on its *first*
    /// appearance only when the first carrier fails, and that path has to stop
    /// the walk too. When it did not, this walk went on through all four.
    @Test("a walk whose first carrier fails stops there")
    func aFailingFirstCarrierStopsTheWalk() async {
        var reported: CheckResult?
        do {
            _ = try await checkEveryCarrier(of: Every.elements(
                "length",
                in: (7 ... 10).map { LyingCount(elements: Array(0 ..< $0)) }
            ) { $0.elements.count }) { carrier, options in
                try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
            }
        } catch let violation as PropertyLawViolation {
            reported = violation.results.first(where: \.isViolation)
        } catch {
            Issue.record(error)
        }
        #expect(reported?.counterexample?.hasPrefix("length=count 7 — ") == true)
        #expect(reported?.coverage?.casesRun == 1, "got \(String(describing: reported?.coverage))")
    }

    /// The control: pointed at any single carrier other than the seventh, the
    /// same suite passes. This is what makes the test above a statement about
    /// carrier coverage rather than about the laws.
    @Test("every other single carrier passes the same suite")
    func theSameSuitePassesOnEveryOtherCarrier() async throws {
        for length in [0, 1, 5, 6, 8, 10] {
            let carrier = LyingCount(elements: Array(0 ..< length))
            try await checkCollectionPropertyLaws(
                using: Gen.always(carrier),
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    // MARK: - A suite that throws

    private struct SetupError: Error, Equatable {}

    /// A suite that throws something other than a violation — a carrier that
    /// cannot be built, setup that fails — tested nothing. The walk used to
    /// fold that carrier in as `[]` and count it visited, so a suite that threw
    /// for every carrier returned no results and passed.
    @Test("a suite that throws fails the walk, naming the carrier")
    func aThrowingSuiteFailsTheWalk() async {
        let carriers = honestCarriers()
        await #expect {
            _ = try await checkEveryCarrier(of: carriers) { _, _ in throw SetupError() }
        } throws: { error in
            guard let thrown = error as? CarrierSuiteError else { return false }
            return thrown.carrier == carriers.address(of: 0) && thrown.underlying is SetupError
        }
    }

    /// Carriers before the one that throws ran their laws, and passed; the
    /// error names the carrier that threw, not the first one walked.
    @Test("the error names the carrier whose suite threw")
    func theErrorNamesTheThrowingCarrier() async {
        let carriers = honestCarriers()
        await #expect {
            _ = try await checkEveryCarrier(of: carriers) { carrier, options in
                if carrier.count == 3 { throw SetupError() }
                return try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
            }
        } throws: { error in
            guard let thrown = error as? CarrierSuiteError else { return false }
            // The description is what a failing run shows: it names both the
            // carrier and what the suite threw.
            return thrown.carrier == carriers.address(of: 3)
                && "\(thrown)".contains(carriers.address(of: 3))
                && "\(thrown)".contains("\(SetupError())")
        }
    }

    private actor Visits {
        var seen: [Int] = []

        func add(_ count: Int) { seen.append(count) }
    }

    /// The error naming the right carrier does not show the walk stopped: a
    /// walk that kept going and threw the first error at the end names it too.
    @Test("the walk stops at the carrier whose suite threw")
    func theWalkStopsAtTheThrowingCarrier() async {
        let visits = Visits()
        await #expect(throws: CarrierSuiteError.self) {
            _ = try await checkEveryCarrier(of: honestCarriers()) { carrier, options in
                await visits.add(carrier.count)
                if carrier.count == 3 { throw SetupError() }
                return try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
            }
        }
        #expect(await visits.seen == [0, 1, 2, 3])
    }

    /// Errors that mean *stop* are not this carrier's failure, and wrapped they
    /// could not be recognised: `catch is CancellationError` would miss.
    @Test("cancellation reaches the caller unwrapped")
    func cancellationIsNotWrapped() async {
        await #expect(throws: CancellationError.self) {
            _ = try await checkEveryCarrier(of: honestCarriers()) { _, _ in throw CancellationError() }
        }
    }

    /// Any error thrown once the task is cancelled is passed through, which is
    /// what keeps `Test.cancel()` a cancellation: it cancels the task and throws
    /// a type Swift Testing keeps internal.
    @Test("an error thrown after the task is cancelled is not wrapped")
    func anErrorAfterCancellationIsNotWrapped() async {
        let walk = Task {
            try await checkEveryCarrier(of: honestCarriers()) { _, _ in
                withUnsafeCurrentTask { $0?.cancel() }
                throw SetupError()
            }
        }
        await #expect(throws: SetupError.self) { _ = try await walk.value }
    }

    /// `#require` records its own issue and throws `ExpectationFailedError`,
    /// which Swift Testing does not record again, unless it arrives wrapped.
    @Test("a failed #require inside the suite reaches the caller unwrapped")
    func aFailedRequireIsNotWrapped() async {
        let thrown = Visits()
        await withKnownIssue("the suite's own #require fails, once") {
            do {
                _ = try await checkEveryCarrier(of: honestCarriers()) { carrier, options in
                    try #require(carrier.count < 2)
                    return try await checkCollectionPropertyLaws(using: Gen.always(carrier), options: options)
                }
            } catch is ExpectationFailedError {
                await thrown.add(1)
            }
        }
        #expect(await thrown.seen == [1], "the #require's error should arrive as ExpectationFailedError")
    }

    /// The protocol chains go through the same collector. A parent check
    /// throws only a violation, which is folded into results; anything else
    /// now reaches the caller instead of becoming an empty result.
    @Test("the inherited-law collector rethrows anything but a violation")
    func inheritedCollectorRethrowsNonViolations() async {
        await #expect(throws: SetupError.self) {
            _ = try await collectingInheritedLaws(rebasing: LawCheckOptions()) { _ in throw SetupError() }
        }
    }

    /// The other half: a parent's violation is still folded into results, so the
    /// child decides enforcement once over the merged set.
    @Test("the inherited-law collector folds a violation into its results")
    func inheritedCollectorFoldsAViolation() async throws {
        let folded = CheckResult(
            protocolLaw: "Folded.law",
            tier: .strict,
            trials: 0,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .suppressed(reason: "folded")
        )
        let results = try await collectingInheritedLaws(rebasing: LawCheckOptions()) { _ in
            throw PropertyLawViolation(results: [folded])
        }
        #expect(results.map(\.protocolLaw) == ["Folded.law"])
    }
}
