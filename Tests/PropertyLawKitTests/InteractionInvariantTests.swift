import Testing
@testable import PropertyLawKit

// Helper conformance fixtures (State/Action + invariant conformers) are
// scoped inside the @Suite struct, nesting them one level deeper than the
// rule's default — idiomatic for Swift Testing fixtures.
// swiftlint:disable nesting

// v2.3.0 — InteractionInvariant + the four refining state-predicate
// sub-protocols + ActionIdempotenceInvariant (sibling shape).
// Type-level / conformance-shape coverage only; the verify harness
// proper is consumed by SwiftInferProperties' M9 RefactorBridge.

@Suite("InteractionInvariant — v2.3.0 protocol family")
struct InteractionInvariantTests {

    struct State: Equatable {
        var count: Int
        var items: [Int]
        var isShowingSheet: Bool
        var isShowingAlert: Bool
        var selectedID: Int?
        var isLoading: Bool
        var activeTask: Int?
    }

    enum Action: Hashable {
        case refresh, reset, append(Int), pickSheet, dismiss
    }

    // MARK: - Cardinality

    struct InboxCardinality: CardinalityInvariant {
        static func invariantHolds(in state: State) -> Bool {
            (state.isShowingSheet ? 1 : 0) + (state.isShowingAlert ? 1 : 0) <= 1
        }
    }

    @Test("Cardinality conformance — invariantHolds witnesses the bound")
    func cardinalityHolds() {
        let clean = State(
            count: 0, items: [], isShowingSheet: true, isShowingAlert: false,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        #expect(InboxCardinality.invariantHolds(in: clean))
        let violating = State(
            count: 0, items: [], isShowingSheet: true, isShowingAlert: true,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        #expect(!InboxCardinality.invariantHolds(in: violating))
    }

    // MARK: - Referential Integrity

    struct InboxReferentialIntegrity: ReferentialIntegrityInvariant {
        static func invariantHolds(in state: State) -> Bool {
            state.selectedID == nil || state.items.contains(state.selectedID!)
        }
    }

    @Test("Referential integrity — nil selected ID and present-in-collection both pass")
    func referentialIntegrityHolds() {
        let unselected = State(
            count: 0, items: [1, 2, 3], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        let selectedPresent = State(
            count: 0, items: [1, 2, 3], isShowingSheet: false, isShowingAlert: false,
            selectedID: 2, isLoading: false, activeTask: nil
        )
        let stale = State(
            count: 0, items: [1, 2, 3], isShowingSheet: false, isShowingAlert: false,
            selectedID: 999, isLoading: false, activeTask: nil
        )
        #expect(InboxReferentialIntegrity.invariantHolds(in: unselected))
        #expect(InboxReferentialIntegrity.invariantHolds(in: selectedPresent))
        #expect(!InboxReferentialIntegrity.invariantHolds(in: stale))
    }

    // MARK: - Biconditional

    struct InboxLoadingBiconditional: BiconditionalInvariant {
        static func invariantHolds(in state: State) -> Bool {
            state.isLoading == (state.activeTask != nil)
        }
    }

    @Test("Biconditional — both true / both false satisfy; mismatch violates")
    func biconditionalHolds() {
        let loadingActive = State(
            count: 0, items: [], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: true, activeTask: 7
        )
        let idleNil = State(
            count: 0, items: [], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        let loadingButNil = State(
            count: 0, items: [], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: true, activeTask: nil
        )
        #expect(InboxLoadingBiconditional.invariantHolds(in: loadingActive))
        #expect(InboxLoadingBiconditional.invariantHolds(in: idleNil))
        #expect(!InboxLoadingBiconditional.invariantHolds(in: loadingButNil))
    }

    // MARK: - Conservation

    struct InboxConservation: ConservationInvariant {
        static func invariantHolds(in state: State) -> Bool {
            state.count == state.items.count
        }
    }

    @Test("Conservation — stored count agrees with collection size")
    func conservationHolds() {
        let consistent = State(
            count: 3, items: [1, 2, 3], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        let drifted = State(
            count: 2, items: [1, 2, 3], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        #expect(InboxConservation.invariantHolds(in: consistent))
        #expect(!InboxConservation.invariantHolds(in: drifted))
    }

    // MARK: - ActionIdempotence

    struct InboxActionIdempotence: ActionIdempotenceInvariant {
        typealias State = InteractionInvariantTests.State
        typealias Action = InteractionInvariantTests.Action
        static let idempotentActions: Set<Action> = [.refresh, .reset]
    }

    @Test("ActionIdempotence — idempotentActions set is the declared law")
    func actionIdempotenceCarriesIdempotentActionSet() {
        #expect(InboxActionIdempotence.idempotentActions == [.refresh, .reset])
    }

    @Test("ActionIdempotence — inherited invariantHolds defaults to true")
    func actionIdempotenceInvariantHoldsDefaultsTrue() {
        // The double-apply law is checked by the kit's harness via
        // idempotentActions; the inherited state predicate is
        // intentionally trivial so conformers don't have to write
        // `return true`.
        let anyState = State(
            count: 0, items: [], isShowingSheet: false, isShowingAlert: false,
            selectedID: nil, isLoading: false, activeTask: nil
        )
        #expect(InboxActionIdempotence.invariantHolds(in: anyState))
    }

    // MARK: - Mutual independence (PRD §9.4 — no hierarchy)

    @Test("the five family protocols don't subsume each other — all refine InteractionInvariant directly")
    func familiesAreMutuallyIndependent() {
        // Static-typechecked: each protocol's parent is InteractionInvariant,
        // not another family. Pure type-level assertion.
        func acceptsRoot<I: InteractionInvariant>(_ type: I.Type) {}
        acceptsRoot(InboxCardinality.self)
        acceptsRoot(InboxReferentialIntegrity.self)
        acceptsRoot(InboxLoadingBiconditional.self)
        acceptsRoot(InboxConservation.self)
        acceptsRoot(InboxActionIdempotence.self)
    }
}

// swiftlint:enable nesting
