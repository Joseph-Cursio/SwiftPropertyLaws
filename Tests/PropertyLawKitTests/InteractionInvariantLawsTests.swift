import Testing
import PropertyBased
@testable import PropertyLawKit

/// v2.4.0 — tests for `checkInteractionInvariantPropertyLaws` +
/// `checkActionIdempotenceInvariantPropertyLaws`. Hand-rolled
/// conformers + reducers exercise the positive (invariant always
/// holds) and negative (specific action breaks the invariant)
/// cases.

struct InteractionInvariantLawsTests {

    // MARK: - State-predicate harness — positive control

    @Test func stateInvariantHoldsAcrossAllActions() async throws {
        // Cardinality invariant: at most one of two Bools may be
        // true at once. The reducer maintains the cardinality bound
        // for every action — no violation surfaces.
        let results = try await checkInteractionInvariantPropertyLaws(
            for: TwoFlagCardinality.self,
            initialState: TwoFlagState(showsA: false, showsB: false),
            reducer: { state, action in TwoFlagFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].tier == .strict)
        #expect(results[0].protocolLaw == "InteractionInvariant.invariantHoldsAfterEachStep")
    }

    // MARK: - State-predicate harness — negative control

    @Test func stateInvariantViolatedReportsCounterexample() async throws {
        // Same invariant, but a faulty reducer that sets *both*
        // flags to true on `.showBoth`. The invariant
        // `(showsA ? 1 : 0) + (showsB ? 1 : 0) <= 1` breaks; the
        // harness surfaces a violation with a counterexample
        // including the failing action prefix.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkInteractionInvariantPropertyLaws(
                for: TwoFlagCardinality.self,
                initialState: TwoFlagState(showsA: false, showsB: false),
                reducer: { state, action in TwoFlagFaultyFeature.reduce(state, action) },
                options: LawCheckOptions(budget: .sanity)
            )
        }
        // Only `.showBoth` breaks the invariant, so the reported prefix ends
        // with it. A re-walk that stopped at the first step where the
        // invariant *held* reported a prefix ending in another action.
        let text = violation?.results.first?.counterexample ?? ""
        #expect(text.contains("Invariant violated at step"), "\(text)")
        #expect(text.contains("showBoth]"), "\(text)")
    }

    // MARK: - State-predicate harness — initial-state violation

    @Test func initialStateViolatingInvariantReportedDirectly() async throws {
        // The invariant fails on the *initial* state (both flags
        // start true). The harness should detect this even when
        // the action sequence is empty (length 0...0).
        let violation = await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkInteractionInvariantPropertyLaws(
                for: TwoFlagCardinality.self,
                initialState: TwoFlagState(showsA: true, showsB: true),
                reducer: { state, action in TwoFlagFeature.reduce(state, action) },
                length: 0...0,
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let text = violation?.results.first?.counterexample ?? ""
        #expect(text.contains("Invariant violated by initial state"), "\(text)")
    }

    // MARK: - ActionIdempotence harness — positive control

    @Test func actionIdempotencePassesForIdempotentReducer() async throws {
        // `.reset` sets state to `(0, 0)` — applying twice produces
        // the same final state as applying once. Same for `.toggleA`
        // ... wait, toggle is NOT idempotent. The fixture
        // `CounterIdempotence` declares only `.reset` as
        // idempotent, and the reducer treats `.reset` as a setter
        // (idempotent for same payload).
        let results = try await checkActionIdempotenceInvariantPropertyLaws(
            for: CounterIdempotence.self,
            initialState: CounterState(value: 0, sub: 0),
            reducer: { state, action in CounterFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results[0].protocolLaw == "ActionIdempotenceInvariant.doubleApplicationEqualsSingle")
    }

    // MARK: - ActionIdempotence harness — negative control

    @Test func actionIdempotenceViolatedReportsCounterexample() async throws {
        // The CounterIdempotenceLying conformer claims `.increment`
        // is idempotent, but the reducer increments by 1 each time
        // — applying twice yields a different state. The harness
        // surfaces a violation.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkActionIdempotenceInvariantPropertyLaws(
                for: CounterIdempotenceLying.self,
                initialState: CounterState(value: 0, sub: 0),
                reducer: { state, action in CounterFeature.reduce(state, action) },
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let text = violation?.results.first?.counterexample ?? ""
        #expect(text.contains("Action increment is NOT idempotent"), "\(text)")
    }

    // MARK: - ActionIdempotence harness — empty idempotentActions

    @Test func actionIdempotenceWithEmptySetPassesTrivially() async throws {
        // A conformer with empty `idempotentActions` is a degenerate
        // but valid case — no per-action checks happen; the harness
        // surfaces a pass.
        let results = try await checkActionIdempotenceInvariantPropertyLaws(
            for: CounterIdempotenceEmptySet.self,
            initialState: CounterState(value: 0, sub: 0),
            reducer: { state, action in CounterFeature.reduce(state, action) },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results.allSatisfy { $0.isViolation == false })
    }
}

// MARK: - Fixtures: state-predicate (Cardinality)

struct TwoFlagState: Equatable, Sendable {
    var showsA: Bool
    var showsB: Bool
}

enum TwoFlagAction: CaseIterable, Sendable {
    case showA
    case showB
    case dismissAll
    case showBoth   // the faulty-reducer trigger
}

/// Conformer asserting the Cardinality bound (at most one flag set).
struct TwoFlagCardinality: CardinalityInvariant, Sendable {
    typealias State = TwoFlagState
    static func invariantHolds(in state: TwoFlagState) -> Bool {
        (state.showsA ? 1 : 0) + (state.showsB ? 1 : 0) <= 1
    }
}

/// Well-behaved reducer — every action preserves the cardinality
/// bound. `.showBoth` is treated as `.dismissAll` to keep the
/// invariant holding (positive control).
enum TwoFlagFeature {
    static func reduce(_ state: TwoFlagState, _ action: TwoFlagAction) -> TwoFlagState {
        switch action {
        case .showA: return TwoFlagState(showsA: true, showsB: false)
        case .showB: return TwoFlagState(showsA: false, showsB: true)
        case .dismissAll, .showBoth: return TwoFlagState(showsA: false, showsB: false)
        }
    }
}

/// Faulty reducer — `.showBoth` violates the invariant by setting
/// both flags to true (negative control).
enum TwoFlagFaultyFeature {
    static func reduce(_ state: TwoFlagState, _ action: TwoFlagAction) -> TwoFlagState {
        switch action {
        case .showA: return TwoFlagState(showsA: true, showsB: false)
        case .showB: return TwoFlagState(showsA: false, showsB: true)
        case .dismissAll: return TwoFlagState(showsA: false, showsB: false)
        case .showBoth: return TwoFlagState(showsA: true, showsB: true)
        }
    }
}

// MARK: - Fixtures: ActionIdempotence

struct CounterState: Equatable, Sendable {
    var value: Int
    var sub: Int
}

enum CounterAction: CaseIterable, Sendable, Hashable {
    case increment
    case decrement
    case reset
}

enum CounterFeature {
    static func reduce(_ state: CounterState, _ action: CounterAction) -> CounterState {
        switch action {
        case .increment: return CounterState(value: state.value + 1, sub: state.sub)
        case .decrement: return CounterState(value: state.value - 1, sub: state.sub)
        case .reset: return CounterState(value: 0, sub: 0)
        }
    }
}

/// Honest conformer — only `.reset` is claimed idempotent, and the
/// reducer treats it as a setter (positive control).
struct CounterIdempotence: ActionIdempotenceInvariant, Sendable {
    typealias State = CounterState
    typealias Action = CounterAction
    static let idempotentActions: Set<CounterAction> = [.reset]
}

/// Lying conformer — claims `.increment` is idempotent, but the
/// reducer increments by 1 each time (negative control).
struct CounterIdempotenceLying: ActionIdempotenceInvariant, Sendable {
    typealias State = CounterState
    typealias Action = CounterAction
    static let idempotentActions: Set<CounterAction> = [.increment]
}

/// Empty-set conformer — degenerate but valid; no per-action
/// checks happen (positive control for the empty-set branch).
struct CounterIdempotenceEmptySet: ActionIdempotenceInvariant, Sendable {
    typealias State = CounterState
    typealias Action = CounterAction
    static let idempotentActions: Set<CounterAction> = []
}
