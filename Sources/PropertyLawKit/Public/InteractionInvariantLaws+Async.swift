import PropertyBased

// v2.5.0 — async-reducer overloads of the two interaction-invariant
// harnesses. Follow-through on the reducer-path async slice:
// swift-infer's verify-interaction now admits `@ClockDeterministic`
// async reducers, so the CI-side harness must be able to drive the
// same reducers. Same laws, same `protocolLaw` strings — only the
// reducer call is awaited.
//
// **Counterexample fidelity caveat.** The sync harnesses re-walk the
// failing sequence inside `formatCounterexample` to pinpoint the
// exact failing step; that closure is synchronous, so these overloads
// cannot replay an async reducer there. They report the full failing
// sequence + initial state instead — replaying with the run's seed
// reproduces the step-level detail.

/// Async-reducer overload of `checkInteractionInvariantPropertyLaws`.
/// One Strict-tier law per call — `invariantHoldsAfterEachStep` —
/// checked against the initial state AND after every awaited action.
@discardableResult
public func checkInteractionInvariantPropertyLaws<
    Invariant: InteractionInvariant & Sendable,
    Action: CaseIterable & Sendable
>(
    for invariant: Invariant.Type = Invariant.self,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Action) async -> Invariant.State,
    length: ClosedRange<Int> = ActionSequenceFactory.defaultLength,
    statefulGuards: [any StatefulGuard<Action>] = [],
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where
    Invariant.State: Sendable,
    Action.AllCases: Sendable & RandomAccessCollection {
    try await runPropertyLawSuite(options: options) {
        [
            await checkInvariantHoldsAfterEachStepAsync(
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

/// Async-reducer overload of `checkActionIdempotenceInvariantPropertyLaws`.
/// Per PRD §5.2: drive the reducer to an arbitrary reachable state, then
/// for each `a ∈ idempotentActions` assert the awaited double-application
/// equality `reduce(reduce(s, a), a) == reduce(s, a)`.
@discardableResult
public func checkActionIdempotenceInvariantPropertyLaws<
    Invariant: ActionIdempotenceInvariant & Sendable
>(
    for invariant: Invariant.Type = Invariant.self,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Invariant.Action) async -> Invariant.State,
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
            await checkActionIdempotenceDoubleApplicationAsync(
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

// Mirror the sync per-law helpers' 6-parameter shape; the leading
// `invariant: Invariant.Type` is load-bearing for type inference.
// swiftlint:disable function_parameter_count

private func checkInvariantHoldsAfterEachStepAsync<
    Invariant: InteractionInvariant & Sendable,
    Action: CaseIterable & Sendable
>(
    invariant: Invariant.Type,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Action) async -> Invariant.State,
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
                    state = await reducer(state, action)
                    if !Invariant.invariantHolds(in: state) { return false }
                }
                return true
            },
            formatCounterexample: { actions, _ in
                "Invariant \(Invariant.self) violated along actions \(actions) "
                    + "from initial state \(initialState). (Async reducer: the "
                    + "sync counterexample re-walk is unavailable; replay with "
                    + "this run's seed for the step-level detail.)"
            }
        )
    )
}

private func checkActionIdempotenceDoubleApplicationAsync<
    Invariant: ActionIdempotenceInvariant & Sendable
>(
    invariant: Invariant.Type,
    initialState: Invariant.State,
    reducer: @escaping @Sendable (Invariant.State, Invariant.Action) async -> Invariant.State,
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
                    state = await reducer(state, action)
                }
                for idempotent in Invariant.idempotentActions {
                    let once = await reducer(state, idempotent)
                    let twice = await reducer(once, idempotent)
                    if once != twice { return false }
                }
                return true
            },
            formatCounterexample: { actions, _ in
                "An action in \(Invariant.idempotentActions) is NOT double-apply "
                    + "idempotent on the state reached via \(actions) from initial "
                    + "state \(initialState). (Async reducer: the sync "
                    + "counterexample re-walk is unavailable; replay with this "
                    + "run's seed for the per-action detail.)"
            }
        )
    )
}

// swiftlint:enable function_parameter_count
