import Testing

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
/// A suite that throws anything other than a `PropertyLawViolation` tested
/// nothing for that carrier, so the walk stops there and throws
/// `CarrierSuiteError`, naming the carrier and carrying the error. Errors that
/// mean *stop* rather than *this carrier failed* pass through unwrapped, so
/// callers and the test runner still recognise them: cancellation (including
/// Swift Testing's `Test.cancel()`), a failed `#require`, and a replay
/// mismatch.
///
/// - Parameters:
///   - carriers: subjects to run the suite against, smallest first.
///   - options: enforcement, suppression and replay settings. `budget` is
///     ignored; use `perCarrier`.
///   - perCarrier: trial budget for each individual suite run.
///   - suite: runs the laws for one carrier. It is handed the rebased options
///     and should pass them through.
/// - Throws: `PropertyLawViolation` per `options.enforcement`, or
///   `CarrierSuiteError` when the suite throws anything else for a carrier.
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
            let results: [CheckResult]
            do {
                results = try await collectingInheritedLaws(rebasing: perCarrierOptions) {
                    try await suite(carriers[index], $0)
                }
            } catch where passesThroughUnwrapped(error) {
                throw error
            } catch {
                throw CarrierSuiteError(carrier: carriers.address(of: index), underlying: error)
            }
            merged.absorb(results, carrier: carriers.address(of: index))
            if merged.sawViolation { break }
        }
        return merged.assembled()
    }
}

/// Errors that mean *stop*, not *this carrier's suite failed*. Wrapped in
/// `CarrierSuiteError`, Swift Testing could no longer recognise them: a failed
/// `#require` would be recorded a second time, and `Test.cancel()` — which
/// cancels the task and throws a type Swift Testing keeps internal — would fail
/// the test instead of cancelling it. A replay mismatch is about the run, not
/// the carrier.
private func passesThroughUnwrapped(_ error: any Error) -> Bool {
    Task.isCancelled
        || error is CancellationError
        || error is ExpectationFailedError
        || error is ReplayEnvironmentMismatch
}
