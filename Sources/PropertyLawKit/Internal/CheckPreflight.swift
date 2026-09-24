/// A budget below one trial checks nothing, and a law check must not report that as a pass.
///
/// `TrialBudget.custom(trials:)` carries any `Int`, and an enum case cannot validate its payload,
/// so the refusal lives where a check runs. Before it, `.custom(trials: 0)` ran no trials and
/// reported `.passed` — a green result that checked nothing — and a negative count crashed the
/// backend's `for _ in 0..<trials` with a range error. SwiftInferProperties found the second by
/// proposing `measure-non-negativity` for `trialCount`.
enum CheckPreflight {

    /// The result a check returns without running, or `nil` to run it: a skip suppression first,
    /// then a budget that asks for no trials. Shared by both drivers, which opened with the same two
    /// exits.
    static func earlyResult(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        environment: Environment
    ) -> CheckResult? {
        if let skip = LawSuppressionPolicy.match(protocolLaw: protocolLaw, kind: .skip, in: options.suppressions) {
            return LawSuppressionPolicy.suppressedResult(
                protocolLaw: protocolLaw,
                tier: tier,
                seed: options.seed,
                environment: environment,
                reason: skip.reason
            )
        }
        return emptyBudgetRefusal(protocolLaw: protocolLaw, tier: tier, options: options, environment: environment)
    }

    /// A failed result naming the budget, or `nil` when the budget asks for at least one trial.
    static func emptyBudgetRefusal(
        protocolLaw: String,
        tier: StrictnessTier,
        options: LawCheckOptions,
        environment: Environment
    ) -> CheckResult? {
        let trials = options.budget.trialCount
        guard trials < 1 else { return nil }
        return CheckResult(
            protocolLaw: protocolLaw,
            tier: tier,
            trials: 0,
            seed: options.seed ?? Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: environment,
            outcome: .failed(counterexample: "the budget asks for \(trials) trials, so this law was not "
                + "checked; a budget needs at least one trial")
        )
    }
}
