import PropertyBased

/// Checks that an `InteractionInvariant` forbids *something*.
///
/// Every other law in this kit asks whether the code satisfies the specification. This one asks
/// whether the specification says anything, and it is the only check here whose subject is the
/// thing the caller wrote rather than the thing under test.
///
/// The motivation is a documented hazard in the book that nothing currently catches. Chapter 20's
/// §20.4.2 shows a postcondition that forgot to snapshot the pre-state — `model.count <=
/// model.count + 1` — and observes that it is *"vacuously true and asserts nothing"*. The same
/// mistake in an invariant is `invariantHolds(in:) { true }`, reached by a guard clause that can
/// never be false, an `Optional` that is never populated, or a refactor that removed the field the
/// predicate used to read.
///
/// **A vacuous invariant passes every other law in this file.** `invariantHoldsAfterEachStep`
/// drives a thousand action sequences and reports success, because the invariant it is enforcing
/// is `true`. The suite goes green and the reader believes a property is being checked. That is
/// the failure mode this kit takes most seriously elsewhere — a check that looks like success —
/// and until now the specification itself was the one place it could hide.
///
/// **The test is falsifiability, not "is it ever false in practice".** A *correct* invariant also
/// holds on every reachable state; that is what makes it correct. So reachable states cannot
/// distinguish the two. This law samples states from a generator the caller supplies **without
/// running the reducer**, which is the point: those states are not required to be reachable, and
/// a real invariant will reject some of them. One rejection is enough. An invariant that accepts
/// every state the generator can build is not constraining the state space.
///
/// ```swift
/// try await checkInvariantIsFalsifiable(
///     for: SelectionIntegrity.self,
///     using: Gen<AppState>.arbitrary()
/// )
/// ```
///
/// **This is deliberately not part of `checkInteractionInvariantPropertyLaws`.** That entry point
/// takes an `initialState` and a reducer and never needs a free state generator; requiring one
/// would change its signature for every caller to serve this check. Call this alongside it when
/// you have a generator, which is also when the check is cheap.
///
/// **Conventional tier, deliberately.** A Strict law says "this is a bug". This one can be wrong
/// for a reason outside the caller's control: a generator too narrow to build a violating state
/// makes a *correct* invariant look vacuous. Reporting it is right; failing the build on it is
/// not, and `.strict` enforcement promotes it when a suite wants that. This is the same call
/// §8.6 makes about round-trip fidelity, for the same reason.
///
/// The idea is `swift-collections`' — its `checkEquatable` validates the *oracle* it is handed
/// before judging the type against it, reporting `bad oracle: broken reflexivity` distinctly from
/// a conformance failure. See `planning/conformance-checkers.md` in pbt-book.
@discardableResult
public func checkInvariantIsFalsifiable<
    Invariant: InteractionInvariant & Sendable,
    Shrinker: SendableSequenceType
>(
    for invariant: Invariant.Type = Invariant.self,
    using generator: Generator<Invariant.State, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where Invariant.State: Sendable {
    try await runPropertyLawSuite(options: options) {
        [
            await AggregateDriver.run(
                protocolLaw: "InteractionInvariant.isFalsifiable",
                tier: .conventional,
                options: options
            ) { rng, trials in
                var accepted = 0
                for _ in 0 ..< trials {
                    let state = generator.run(using: &rng)
                    if Invariant.invariantHolds(in: state) {
                        accepted += 1
                    } else {
                        // One rejection is all the law asks for: the predicate
                        // distinguishes between states, so it constrains something.
                        return .passed
                    }
                }
                return .failed(
                    counterexample: """
                    \(Invariant.self).invariantHolds(in:) accepted all \(accepted) generated \
                    states, so it forbids nothing and every sequence-level law over it passes \
                    for free.

                    This is a claim about the invariant, not about the code under test. The \
                    usual causes are a predicate that lost the field it used to read, a guard \
                    clause that cannot be false, or an `invariantHolds` that returns a constant.

                    If the invariant is genuinely meant to hold everywhere, it is not an \
                    invariant — it is a fact about the type, and belongs in the type. If it is \
                    meant to forbid something, the generator may be too narrow to build a state \
                    that violates it; widen the generator before changing the predicate.
                    """
                )
            }
        ]
    }
}
