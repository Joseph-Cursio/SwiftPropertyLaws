/// Walks a bounded input space in full, smallest case first.
///
/// The third driver, beside `PerLawDriver` (per-trial, backend-driven) and
/// `AggregateDriver` (whole-budget, backend-free). Like `AggregateDriver` it
/// bypasses `PropertyBackend` deliberately: there is nothing for a backend to
/// vary. The walk is a `for` loop over `0 ..< count` in a fixed order, so every
/// backend would produce the same result, and threading it through the protocol
/// would only invite a backend to reorder the one thing that must not be
/// reordered.
///
/// **No shrinker, and none is needed.** Shrinking exists to turn a large random
/// counterexample into a small one. `Enumeration` orders its cases smallest
/// first, so the first failure found is already the smallest failure that
/// exists — not the smallest one a greedy descent happened to reach.
package enum EnumerationDriver {

    /// Marker seed for a walk, which consumes no randomness. Recorded because
    /// `CheckResult.seed` is non-optional; never used, and never printed —
    /// `ViolationFormatter` renders the coverage line instead, because a walk
    /// replays from its own definition rather than from a seed. The zeroed
    /// state is the kit's existing "no RNG was consumed" marker: it is what
    /// `LawSuppressionPolicy.suppressedResult` already records for a skipped
    /// law, for the same reason.
    private static let inertSeed = Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0)

    package static func run<Element: Sendable>(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        space: Enumeration<Element>,
        property: @Sendable (Element) async throws -> Bool,
        describeFailure: (@Sendable (Element, ErrorBox?) -> String)? = nil
    ) async -> CheckResult {
        let environment = Environment.current(backend: options.backend)
        if let skip = LawSuppressionPolicy.match(
            protocolLaw: protocolLaw,
            kind: .skip,
            in: options.suppressions
        ) {
            return LawSuppressionPolicy.suppressedResult(
                protocolLaw: protocolLaw,
                tier: tier,
                seed: options.seed ?? inertSeed,
                environment: environment,
                reason: skip.reason
            )
        }
        var outcome: CheckResult.Outcome = .passed
        var casesRun = 0
        walk: for index in space.indices {
            casesRun = index + 1
            do {
                if try await property(space[index]) == false {
                    outcome = .failed(counterexample: describe(space, index, nil, describeFailure))
                    break walk
                }
            } catch {
                let boxed = ErrorBox(error)
                outcome = .failed(counterexample: describe(space, index, boxed, describeFailure))
                break walk
            }
        }
        let raw = CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: casesRun,
            seed: options.seed ?? inertSeed,
            environment: environment,
            outcome: outcome,
            coverage: SpaceCoverage(casesRun: casesRun, spaceSize: space.fullCount)
        )
        return LawSuppressionPolicy.rewriteIfIntentional(raw, in: options.suppressions)
    }

    /// The address says *where* in the space the failure is; a law's own
    /// formatter says *why* it failed. Both are worth having, so both are
    /// reported — the address first, because it is what makes the case
    /// reproducible without a seed.
    private static func describe<Element: Sendable>(
        _ space: Enumeration<Element>,
        _ index: Int,
        _ thrown: ErrorBox?,
        _ describeFailure: (@Sendable (Element, ErrorBox?) -> String)?
    ) -> String {
        let address = space.address(of: index)
        guard let describeFailure else {
            return thrown.map { "\(address); threw \($0.message)" } ?? address
        }
        return "\(address) — \(describeFailure(space[index], thrown))"
    }
}
