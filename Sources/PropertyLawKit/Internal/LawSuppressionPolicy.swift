/// Shared suppression policy for `PerLawDriver` and `AggregateDriver` (PRD §4.7).
///
/// `.skip` returns a synthesized `.suppressed` result without paying the trial
/// budget. `.intentionalViolation` rewrites a `.failed` outcome to
/// `.expectedViolation` after the check has run.
internal enum LawSuppressionPolicy {

    static func match(
        protocolLaw: String,
        kind: LawSuppression.Kind,
        in suppressions: [LawSuppression]
    ) -> LawSuppression? {
        suppressions.first { $0.identifier.matches(protocolLaw) && $0.kind == kind }
    }

    static func suppressedResult(
        protocolLaw: String,
        tier: StrictnessTier,
        seed: Seed?,
        environment: Environment,
        reason: String
    ) -> CheckResult {
        // No RNG was consumed; preserve any caller-provided seed so re-runs
        // of the same options stay deterministic.
        let resolvedSeed = seed ?? Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0)
        return CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: 0,
            seed: resolvedSeed,
            environment: environment,
            outcome: .suppressed(reason: reason)
        )
    }

    static func rewriteIfIntentional(
        _ raw: CheckResult,
        in suppressions: [LawSuppression]
    ) -> CheckResult {
        guard case .failed(let counterexample) = raw.outcome else { return raw }
        guard let intent = match(
            protocolLaw: raw.protocolLaw,
            kind: .intentionalViolation,
            in: suppressions
        ) else { return raw }
        // **Mutate a copy.** The rebuild this replaces named eight of `CheckResult`'s TWELVE fields,
        // so `shrunkFrom`, `shrinkSteps`, `inputClasses` and `boundaryHits` were silently discarded
        // whenever a failure was reclassified as an intentional violation — the shrunk
        // counterexample and every coverage statistic, gone, with nothing to show it. The
        // initialiser's parameters have defaults, so the omission compiled.
        //
        // Only the outcome is meant to change here.
        var reclassified = raw
        reclassified.outcome = .expectedViolation(
            reason: intent.reason,
            counterexample: counterexample
        )
        return reclassified
    }
}
