import Foundation

/// Counts how often a conditional law's antecedent held.
///
/// Four of the six laws here are conditional — `guard compare(a, b), compare(b, c)`,
/// `guard first == second`, and so on — and **a conditional law whose antecedent
/// never fires reports `.passed` having tested nothing.** That is not a
/// hypothetical: `congruence` needs the generator to produce two equal values,
/// which over a wide domain is close to never, so the law goes green for free on
/// exactly the callers most likely to need it.
///
/// This is the same fault `checkInvariantIsFalsifiable` exists to catch, one
/// level down: there the *invariant* forbids nothing, here the *law* applies to
/// nothing. Both are specifications that cannot fail.
final class Applications: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.lock(); count += 1; lock.unlock() }
    var recorded: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Turn a vacuous pass into a reported failure, saying accurately *why* the law
/// never applied.
///
/// Conventional tier: neither cause is the law's fault, so this reports rather
/// than throws — `.strict` promotes it.
///
/// **This is a floor, not a defence.** It reports a law that never applied. It
/// says nothing about a law that applied only to cases which could not have
/// refuted it — measured on a non-transitive `==` over a 100-value domain, the
/// antecedent fired twice per thousand trials and the refuting configuration
/// zero times, so a counter would have reported the law as working. No counter
/// can close that gap: telling a *telling* application from a harmless one needs
/// the answer you were looking for. Walking the carrier does close it, by
/// applying the law to every case rather than hoping the sample was telling.
///
/// **The two causes of never-applying are not the same finding, and only a
/// complete walk can tell them apart.** Sampled, a zero-application run means "the draws never produced
/// a qualifying case", which might be a narrow generator or might be a case that
/// cannot exist — the count is zero either way and the harness cannot see which.
/// Over a walk that covered its whole space the second reading is the only one
/// left, so the report stops being advice about the generator and becomes a fact
/// about the carrier. A *truncated* walk is back in the ambiguous case and is
/// treated as sampled, because the cases it did not reach are exactly the ones
/// that would have decided the question.
func requiringApplicableCases(
    _ result: CheckResult,
    _ applications: Applications,
    needing description: String,
    tier: StrictnessTier = .conventional
) -> CheckResult {
    guard case .passed = result.outcome, applications.recorded == 0 else { return result }
    let complete = result.coverage?.isComplete ?? false
    let counterexample = complete
        ? """
            vacuous: none of the \(result.trials) cases walked contains \(description), so this \
            law was never applied and its pass means nothing. The walk was complete, so this is a \
            property of the carrier rather than of sampling — widen the carrier; no budget will help.
            """
        : """
            vacuous: across \(result.trials) trials the generator never produced \
            \(description), so this law was never applied and its pass means nothing. \
            Widen the generator, or narrow the domain so the case is reachable.
            """
    return CheckResult(
        protocolLaw: result.protocolLaw,
        tier: tier,
        trials: result.trials,
        seed: result.seed,
        environment: result.environment,
        outcome: .failed(counterexample: counterexample),
        nearMisses: result.nearMisses,
        coverageHints: result.coverageHints,
        shrunkFrom: result.shrunkFrom,
        shrinkSteps: result.shrinkSteps,
        coverage: result.coverage
    )
}
