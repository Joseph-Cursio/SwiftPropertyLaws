import PropertyBased

/// v2.4.0 — runtime harness that drives an `InteractionInvariant`
/// conformer's state-level predicate against random action
/// sequences applied to a user-provided reducer closure.
/// SwiftInferProperties v2.0 M9's RefactorBridge proposes
/// invariant conformers; this harness is what the conformer needs
/// to run those proposals on CI (via the macro discovery
/// integration on the SwiftInferProperties side, queued as a
/// separate cycle).
///
/// **One Strict-tier law per call** —
/// `invariantHoldsAfterEachStep` — `Invariant.invariantHolds(in:)`
/// must hold against the initial state AND after every action in
/// the sampled sequence. A violation reports the prefix of actions
/// that drove the state to the failing configuration.
///
/// **Why per-step, not just post-loop.** The invariant is a
/// permanent property of the State (per PRD §5 / §9); a single
/// step that breaks it is the bug, even if a subsequent step
/// happens to repair it. Per-step checks catch transient
/// violations the post-loop check would miss.
///
/// **Generator caveat.** For `Action: CaseIterable`, this
/// convenience entry uses `Gen<Action>.case` (uniform). Domains
/// where some actions are far more / less common than others
/// should construct their own `Generator<Action, _>` via the
/// primary `ActionSequenceFactory.actionSequence(from:length:statefulGuards:)`
/// entry. Stateful guards filter at the sequence level (drop
/// candidate actions that wouldn't be allowed in the running
/// history) — pass them via `statefulGuards`.
@discardableResult
public func checkInteractionInvariantPropertyLaws<
    Invariant: InteractionInvariant & Sendable,
    Action: CaseIterable & Sendable
>(
    for invariant: Invariant.Type = Invariant.self,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Action) -> Invariant.State,
    length: ClosedRange<Int> = ActionSequenceFactory.defaultLength,
    statefulGuards: [any StatefulGuard<Action>] = [],
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where
    Invariant.State: Sendable,
    Action.AllCases: Sendable & RandomAccessCollection {
    try await runPropertyLawSuite(options: options) {
        [
            await checkInvariantHoldsAfterEachStep(
                invariant: invariant,
                initialState: initialState,
                reducer: reducer,
                length: length,
                statefulGuards: statefulGuards,
                options: options
            )
        ]
    }
}

/// v2.4.0 — runtime harness for `ActionIdempotenceInvariant`. Per
/// PRD §5.2, an action in `Invariant.idempotentActions` is
/// idempotent if `reducer(reducer(s, a), a) == reducer(s, a)` for
/// every reachable State `s`. This harness samples action
/// sequences, applies them to drive the reducer to an arbitrary
/// reachable state, then for each idempotent action checks the
/// double-application equality on that state.
///
/// **The `idempotentActions` set is part of the conformance**, so
/// the harness has no out-of-band action list to consult — the
/// kit reads it from the conformer's static property. An empty
/// set is a degenerate (but valid) conformance and produces no
/// per-action checks; the harness reports a zero-trial-but-passing
/// result so the CI surface stays consistent.
@discardableResult
public func checkActionIdempotenceInvariantPropertyLaws<
    Invariant: ActionIdempotenceInvariant & Sendable
>(
    for invariant: Invariant.Type = Invariant.self,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Invariant.Action) -> Invariant.State,
    length: ClosedRange<Int> = ActionSequenceFactory.defaultLength,
    statefulGuards: [any StatefulGuard<Invariant.Action>] = [],
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where
    Invariant.State: Sendable,
    Invariant.Action: CaseIterable & Sendable,
    Invariant.Action.AllCases: Sendable & RandomAccessCollection {
    try await runPropertyLawSuite(options: options) {
        [
            await checkActionIdempotenceDoubleApplication(
                invariant: invariant,
                initialState: initialState,
                reducer: reducer,
                length: length,
                statefulGuards: statefulGuards,
                options: options
            )
        ]
    }
}

// MARK: - Per-law internals

// Both per-law helpers mirror their public harness's 6-parameter shape; the
// leading `invariant: Invariant.Type` is load-bearing for type inference (the
// generic `Invariant` isn't deducible from `Invariant.State` alone), so it
// can't be dropped to satisfy the parameter-count rule.
// swiftlint:disable function_parameter_count

/// v2.4.0 — per-step invariant check. Sample an action sequence,
/// apply it step-by-step, verify `invariantHolds` after each step.
/// Violation reports the action prefix that drove the state to
/// the failing configuration.
private func checkInvariantHoldsAfterEachStep<
    Invariant: InteractionInvariant & Sendable,
    Action: CaseIterable & Sendable
>(
    invariant: Invariant.Type,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Action) -> Invariant.State,
    length: ClosedRange<Int>,
    statefulGuards: [any StatefulGuard<Action>],
    options: LawCheckOptions
) async -> CheckResult
where
    Invariant.State: Sendable,
    Action.AllCases: Sendable & RandomAccessCollection {
    let sequenceGen = ActionSequenceFactory.actionSequence(
        forCaseIterable: Action.self,
        length: length,
        statefulGuards: statefulGuards
    )
    return await PerLawDriver.run(
        protocolLaw: "InteractionInvariant.invariantHoldsAfterEachStep",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in sequenceGen.run(using: &rng) },
            property: { actions in
                var state = initialState
                if !Invariant.invariantHolds(in: state) { return false }
                for action in actions {
                    state = reducer(state, action)
                    if !Invariant.invariantHolds(in: state) { return false }
                }
                return true
            },
            formatCounterexample: { actions, _ in
                formatInvariantViolation(
                    of: Invariant.self,
                    initialState: initialState,
                    reducer: reducer,
                    actions: actions
                )
            }
        )
    )
}

/// v2.4.0 — per-action idempotence check.  Sample an action
/// sequence, apply it to drive the reducer to an arbitrary
/// reachable state, then for each `a ∈ idempotentActions` assert
/// `reducer(reducer(s, a), a) == reducer(s, a)`.
private func checkActionIdempotenceDoubleApplication<
    Invariant: ActionIdempotenceInvariant & Sendable
>(
    invariant: Invariant.Type,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Invariant.Action) -> Invariant.State,
    length: ClosedRange<Int>,
    statefulGuards: [any StatefulGuard<Invariant.Action>],
    options: LawCheckOptions
) async -> CheckResult
where
    Invariant.State: Sendable,
    Invariant.Action: CaseIterable & Sendable,
    Invariant.Action.AllCases: Sendable & RandomAccessCollection {
    let sequenceGen = ActionSequenceFactory.actionSequence(
        forCaseIterable: Invariant.Action.self,
        length: length,
        statefulGuards: statefulGuards
    )
    return await PerLawDriver.run(
        protocolLaw: "ActionIdempotenceInvariant.doubleApplicationEqualsSingle",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in sequenceGen.run(using: &rng) },
            property: { actions in
                var state = initialState
                for action in actions {
                    state = reducer(state, action)
                }
                for idempotent in Invariant.idempotentActions {
                    let once = reducer(state, idempotent)
                    let twice = reducer(once, idempotent)
                    if once != twice { return false }
                }
                return true
            },
            formatCounterexample: { actions, _ in
                formatActionIdempotenceViolation(
                    of: Invariant.self,
                    initialState: initialState,
                    reducer: reducer,
                    actions: actions
                )
            }
        )
    )
}

// swiftlint:enable function_parameter_count

// MARK: - Counterexample formatting

/// v2.4.0 — reconstruct the failing step from the failing action
/// sequence. The state-predicate harness's property is `True` if
/// the invariant holds throughout; when it returns `False`, this
/// helper walks the sequence again to find the first step that
/// broke the invariant + reports it. `Invariant.Type` is passed as
/// the leading `of:` parameter only for type-inference; the body
/// references `Invariant.invariantHolds` via the static dispatch.
private func formatInvariantViolation<
    Invariant: InteractionInvariant,
    Action
>(
    of invariantType: Invariant.Type,
    initialState: Invariant.State,
    reducer: (Invariant.State, Action) -> Invariant.State,
    actions: [Action]
) -> String {
    var state = initialState
    if !Invariant.invariantHolds(in: state) {
        return "Invariant violated by initial state \(state) "
            + "(before any actions applied)."
    }
    for (index, action) in actions.enumerated() {
        state = reducer(state, action)
        if !Invariant.invariantHolds(in: state) {
            let prefix = Array(actions.prefix(index + 1))
            return "Invariant violated at step \(index + 1) "
                + "after applying actions \(prefix); "
                + "resulting state: \(state)."
        }
    }
    return "Unexpected: property returned false but no failing "
        + "step found on re-walk. Reducer may be non-deterministic."
}

/// v2.4.0 — reconstruct the failing idempotent action from the
/// drove-to-state sequence. The action-idempotence harness's
/// property is `True` if every idempotent action is double-apply-
/// idempotent on the drove-to state; when it returns `False`,
/// this helper drives to the same state and reports which action
/// failed plus the two resulting states.
private func formatActionIdempotenceViolation<
    Invariant: ActionIdempotenceInvariant
>(
    of invariantType: Invariant.Type,
    initialState: Invariant.State,
    reducer: (Invariant.State, Invariant.Action) -> Invariant.State,
    actions: [Invariant.Action]
) -> String {
    var state = initialState
    for action in actions {
        state = reducer(state, action)
    }
    for idempotent in Invariant.idempotentActions {
        let once = reducer(state, idempotent)
        let twice = reducer(once, idempotent)
        if once != twice {
            return "Action \(idempotent) is NOT idempotent on state "
                + "\(state) (reached via \(actions)). "
                + "reducer(reducer(s, a), a) = \(twice); "
                + "reducer(s, a) = \(once)."
        }
    }
    return "Unexpected: property returned false but no failing "
        + "action found on re-walk. Reducer may be non-deterministic."
}
