import PropertyBased
@testable import PropertyLawKit
import Testing

/// v2.5.0 — tests for the async-reducer overloads of the
/// interaction-invariant harnesses. Reuses the sync suite's
/// fixtures (`TwoFlag*`, `Counter*`) with the reducers lifted to
/// `async` — the awaited path must accept what the sync path
/// accepts and reject what it rejects.
struct InteractionInvariantAsyncLawsTests {

    // MARK: - State-predicate harness

    @Test func asyncStateInvariantHoldsAcrossAllActions() async throws {
        let results = try await checkInteractionInvariantPropertyLaws(
            for: TwoFlagCardinality.self,
            initialState: TwoFlagState(showsA: false, showsB: false),
            reducer: { state, action async in TwoFlagFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].tier == .strict)
        #expect(results[0].protocolLaw == "InteractionInvariant.invariantHoldsAfterEachStep")
    }

    @Test func asyncStateInvariantViolatedThrows() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkInteractionInvariantPropertyLaws(
                for: TwoFlagCardinality.self,
                initialState: TwoFlagState(showsA: false, showsB: false),
                reducer: { state, action async in TwoFlagFaultyFeature.reduce(state, action) },
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    @Test func asyncInitialStateViolationDetectedWithEmptySequence() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkInteractionInvariantPropertyLaws(
                for: TwoFlagCardinality.self,
                initialState: TwoFlagState(showsA: true, showsB: true),
                reducer: { state, action async in TwoFlagFeature.reduce(state, action) },
                length: 0...0,
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    // MARK: - ActionIdempotence harness

    @Test func asyncActionIdempotenceHoldsForHonestConformer() async throws {
        let results = try await checkActionIdempotenceInvariantPropertyLaws(
            for: CounterIdempotence.self,
            initialState: CounterState(value: 0, sub: 0),
            reducer: { state, action async in CounterFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].protocolLaw == "ActionIdempotenceInvariant.doubleApplicationEqualsSingle")
    }

    @Test func asyncActionIdempotenceLyingConformerThrows() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkActionIdempotenceInvariantPropertyLaws(
                for: CounterIdempotenceLying.self,
                initialState: CounterState(value: 0, sub: 0),
                reducer: { state, action async in CounterFeature.reduce(state, action) },
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    // MARK: - A genuinely suspending reducer

    @Test func genuinelySuspendingReducerRunsTheLaw() async throws {
        // The overloads must handle a reducer that actually suspends,
        // not just a sync closure lifted to async.
        let results = try await checkInteractionInvariantPropertyLaws(
            for: TwoFlagCardinality.self,
            initialState: TwoFlagState(showsA: false, showsB: false),
            reducer: { state, action async in
                await Task.yield()
                return TwoFlagFeature.reduce(state, action)
            },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.isViolation == false })
    }
}
