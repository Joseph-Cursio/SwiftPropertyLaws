/// Run an existing law suite once per **carrier**, over a bounded space of
/// carriers.
///
/// The other entry points vary the law's *inputs*. This one varies the *subject*
/// — it is the shape of `withEveryDeque(ofCapacities:)` in swift-collections'
/// test support, where a whole conformance check is re-run against every
/// internal arrangement a `Deque` can be in.
///
/// ```swift
/// try await checkEveryCarrier(of: DequeLayouts.everyLayout()) { deque, options in
///     try await checkCollectionPropertyLaws(using: Gen.always(deque), options: options)
/// }
/// ```
///
/// ## The budget convention, which is the whole design problem
///
/// Apple can afford this because their checkers are *deterministic*: one pass
/// per carrier and the carrier is exhausted. Ours **sample**, so a naive
/// composition multiplies — 107 carriers × 1 000 trials × 15 laws is 1.6 million
/// property evaluations from one innocuous-looking call, which is not what a
/// caller expects and not what they should silently get.
///
/// So the per-carrier budget is a **separate, explicit parameter** defaulting to
/// `.sanity`, and `options.budget` is ignored. That default is not timidity: the
/// variety in a carrier walk comes from the carriers, not from the trials. A
/// hundred deque layouts at a hundred trials each explores far more of what
/// matters than one layout at ten thousand. Raise `perCarrier` when the *inputs*
/// are the interesting axis and the carriers are few.
///
/// ## What it reports
///
/// One `CheckResult` per law, merged across carriers, with `trials` summing the
/// inputs actually drawn for that law and `coverage` describing the **carrier**
/// space rather than the law's input space — the walk this call performed.
///
/// The walk stops at the first carrier that fails any law, so the reported
/// carrier is the smallest one exhibiting the failure, and the counterexample
/// names it: `deque=[0, 1, 2] — <the law's own explanation>`.
///
/// - Parameters:
///   - carriers: subjects to run the suite against, smallest first.
///   - options: enforcement, suppression and replay settings. `budget` is
///     ignored; use `perCarrier`.
///   - perCarrier: trial budget for each individual suite run.
///   - suite: runs the laws for one carrier. It is handed the rebased options
///     and should pass them through.
@discardableResult
public func checkEveryCarrier<Carrier: Sendable>(
    of carriers: Enumeration<Carrier>,
    options: LawCheckOptions = LawCheckOptions(),
    perCarrier: TrialBudget = .sanity,
    suite: @Sendable (Carrier, LawCheckOptions) async throws -> [CheckResult]
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var merged = MergedCarrierResults(spaceSize: carriers.fullCount)
        var perCarrierOptions = options
        perCarrierOptions.budget = perCarrier
        for index in carriers.indices {
            let results = await collectingInheritedLaws(rebasing: perCarrierOptions) {
                try await suite(carriers[index], $0)
            }
            merged.absorb(results, carrier: carriers.address(of: index))
            if merged.sawViolation { break }
        }
        return merged.assembled()
    }
}

/// Folds one `CheckResult` per law out of many per-carrier runs.
///
/// Keyed on `protocolLaw` and ordered by first appearance, so the merged output
/// reads in the same order a single run of the suite would.
private struct MergedCarrierResults {
    private var order: [String] = []
    private var byLaw: [String: CheckResult] = [:]
    private var carriersVisited = 0
    private let spaceSize: Int

    private(set) var sawViolation = false

    init(spaceSize: Int) {
        self.spaceSize = spaceSize
    }

    mutating func absorb(_ results: [CheckResult], carrier: String) {
        carriersVisited += 1
        for result in results {
            guard var running = byLaw[result.protocolLaw] else {
                order.append(result.protocolLaw)
                byLaw[result.protocolLaw] = attributing(result, to: carrier)
                sawViolation = sawViolation || result.isViolation
                continue
            }
            // A law that already failed keeps its first (smallest) carrier;
            // otherwise accumulate the trials and take this carrier's outcome.
            if running.isViolation {
                continue
            }
            running.trials += result.trials
            if result.isViolation {
                let attributed = attributing(result, to: carrier)
                running.outcome = attributed.outcome
            }
            byLaw[result.protocolLaw] = running
            sawViolation = sawViolation || result.isViolation
        }
    }

    /// Name the carrier in the counterexample. The address is what makes the
    /// case reproducible; the law's own text is what explains it.
    private func attributing(_ result: CheckResult, to carrier: String) -> CheckResult {
        guard case .failed(let counterexample) = result.outcome else { return result }
        var attributed = result
        attributed.outcome = .failed(counterexample: "\(carrier) — \(counterexample)")
        return attributed
    }

    func assembled() -> [CheckResult] {
        order.compactMap { name in
            guard var result = byLaw[name] else { return nil }
            result.coverage = SpaceCoverage(casesRun: carriersVisited, spaceSize: spaceSize)
            return result
        }
    }
}
