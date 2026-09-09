import PropertyBased
import Testing
@testable import PropertyLawKit

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
            in: (0 ... bound).map { LyingCount(elements: Array(0 ..< $0)) },
            size: { $0.elements.count }
        )
    }

    private func honestCarriers() -> Enumeration<[Int]> {
        Every.elements("array", in: (0 ... 6).map { Array(0 ..< $0) }, size: { $0.count })
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
            options: LawCheckOptions(budget: .exhaustive(10_000)),
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
            reported = violation.results.first { $0.isViolation }
        } catch {}
        let result = try? #require(reported)
        #expect(result?.isViolation == true)
        // Carriers are walked smallest first, so the reported one is the
        // shortest collection that misreports — length 7, not 8, 9 or 10.
        #expect(result?.counterexample?.hasPrefix("length=count 7 — ") == true,
                "got \(result?.counterexample ?? "nil")")
        #expect(result?.coverage?.casesRun == 8, "the walk should stop at the eighth carrier")
        #expect(result?.coverage?.isComplete == false)
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
}
