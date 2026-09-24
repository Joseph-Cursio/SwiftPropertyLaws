import PropertyBased

/// Aggregate-mode counterpart to `PerLawDriver` for laws that judge an
/// entire trial budget in one shot rather than per-trial (e.g.
/// `Hashable.distribution`).
///
/// The `PropertyBackend` protocol intentionally doesn't model aggregate
/// laws — both backends would loop identically and report a single
/// pass/fail. Keeping aggregate on the kit side avoids inflating the
/// public protocol's surface for a path with no backend divergence.
internal enum AggregateDriver {

    /// Outcome of an aggregate check. The closure decides pass/fail and
    /// supplies the counterexample inline (it has access to the running
    /// sample set the backend would otherwise need to replay).
    enum Outcome: Sendable {
        case passed
        case failed(counterexample: String)
    }

    /// Per-aggregate observation hooks. Bundled so `run`'s parameter count
    /// stays under the lint and individual call sites can opt into a single
    /// concern without naming the others.
    struct Observation: Sendable {
        let nearMissCollector: NearMissCollector?
        let coverageAccumulator: CoverageAccumulator?

        init(
            nearMissCollector: NearMissCollector? = nil,
            coverageAccumulator: CoverageAccumulator? = nil
        ) {
            self.nearMissCollector = nearMissCollector
            self.coverageAccumulator = coverageAccumulator
        }
    }

    static func run(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        observation: Observation = Observation(),
        check: @Sendable (inout Xoshiro, Int) async throws -> Outcome
    ) async -> CheckResult {
        let environment = Environment.current(backend: options.backend)
        if let early = CheckPreflight.earlyResult(
            protocolLaw: protocolLaw, tier: tier, options: options, environment: environment
        ) {
            return early
        }
        var rng = options.seed?.makeXoshiro() ?? Xoshiro()
        let initialSeed = Seed(xoshiro: rng)
        let trials = options.budget.trialCount
        let outcome: CheckResult.Outcome
        do {
            switch try await check(&rng, trials) {
            case .passed:
                outcome = .passed
            case .failed(let counterexample):
                outcome = .failed(counterexample: counterexample)
            }
        } catch {
            outcome = .failed(counterexample: "aggregate check threw: \(error)")
        }
        let raw = CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: trials,
            seed: initialSeed,
            environment: environment,
            outcome: outcome,
            nearMisses: observation.nearMissCollector?.snapshot(),
            coverageHints: observation.coverageAccumulator?.snapshot()
        )
        return LawSuppressionPolicy.rewriteIfIntentional(
            raw,
            in: options.suppressions
        )
    }
}
