import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

/// v2.5.0 — golden-output tests for the `@InteractionInvariantTests`
/// peer macro. One test per family + a negative for the
/// no-conformance diagnostic path. Mirrors `MacroExpansionTests`
/// shape (assertMacroExpansion + per-test macro registry).

nonisolated(unsafe) let interactionTestsMacros: [String: Macro.Type] = [
    "InteractionInvariantTests": InteractionInvariantTestsMacro.self
]

struct InteractionInvariantTestsMacroTests {

    @Test func cardinalityEmitsStatePredicateHarness() {
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct InboxCardinality: CardinalityInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }
            """,
            expandedSource: """
            struct InboxCardinality: CardinalityInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }

            struct InboxCardinalityInteractionInvariantTests {
                @Test func cardinalityInvariant_InboxCardinality() async throws {
                        try await checkInteractionInvariantPropertyLaws(
                            for: InboxCardinality.self,
                            initialState: InboxCardinality.initialState,
                            reducer: InboxCardinality.reducer
                        )
                    }
            }
            """,
            macros: interactionTestsMacros
        )
    }

    @Test func referentialIntegrityEmitsStatePredicateHarness() {
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct InboxRefInt: ReferentialIntegrityInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }
            """,
            expandedSource: """
            struct InboxRefInt: ReferentialIntegrityInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }

            struct InboxRefIntInteractionInvariantTests {
                @Test func referentialIntegrityInvariant_InboxRefInt() async throws {
                        try await checkInteractionInvariantPropertyLaws(
                            for: InboxRefInt.self,
                            initialState: InboxRefInt.initialState,
                            reducer: InboxRefInt.reducer
                        )
                    }
            }
            """,
            macros: interactionTestsMacros
        )
    }

    @Test func biconditionalEmitsStatePredicateHarness() {
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct InboxBicond: BiconditionalInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }
            """,
            expandedSource: """
            struct InboxBicond: BiconditionalInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }

            struct InboxBicondInteractionInvariantTests {
                @Test func biconditionalInvariant_InboxBicond() async throws {
                        try await checkInteractionInvariantPropertyLaws(
                            for: InboxBicond.self,
                            initialState: InboxBicond.initialState,
                            reducer: InboxBicond.reducer
                        )
                    }
            }
            """,
            macros: interactionTestsMacros
        )
    }

    @Test func conservationEmitsStatePredicateHarness() {
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct InboxCons: ConservationInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }
            """,
            expandedSource: """
            struct InboxCons: ConservationInvariant {
                typealias State = InboxState
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
                static func invariantHolds(in state: InboxState) -> Bool { true }
            }

            struct InboxConsInteractionInvariantTests {
                @Test func conservationInvariant_InboxCons() async throws {
                        try await checkInteractionInvariantPropertyLaws(
                            for: InboxCons.self,
                            initialState: InboxCons.initialState,
                            reducer: InboxCons.reducer
                        )
                    }
            }
            """,
            macros: interactionTestsMacros
        )
    }

    @Test func actionIdempotenceEmitsDoubleApplicationHarness() {
        // ActionIdempotence routes to a different harness function
        // (`checkActionIdempotenceInvariantPropertyLaws`); the family
        // detector must classify this case ahead of the root-only
        // `InteractionInvariant` arm so the correct harness emits.
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct InboxIdem: ActionIdempotenceInvariant {
                typealias State = InboxState
                typealias Action = InboxAction
                static let idempotentActions: Set<InboxAction> = []
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
            }
            """,
            expandedSource: """
            struct InboxIdem: ActionIdempotenceInvariant {
                typealias State = InboxState
                typealias Action = InboxAction
                static let idempotentActions: Set<InboxAction> = []
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
            }

            struct InboxIdemInteractionInvariantTests {
                @Test func actionIdempotenceInvariant_InboxIdem() async throws {
                        try await checkActionIdempotenceInvariantPropertyLaws(
                            for: InboxIdem.self,
                            initialState: InboxIdem.initialState,
                            reducer: InboxIdem.reducer
                        )
                    }
            }
            """,
            macros: interactionTestsMacros
        )
    }

    @Test func combinedConformancesPreferActionIdempotenceOverRoot() {
        // ActionIdempotenceInvariant refines InteractionInvariant.
        // If both appear in the inheritance clause, ActionIdempotence
        // must win (it routes to a different harness). The detector's
        // arm order is the load-bearing piece.
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct DualConformer: InteractionInvariant, ActionIdempotenceInvariant {
                typealias State = InboxState
                typealias Action = InboxAction
                static let idempotentActions: Set<InboxAction> = []
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
            }
            """,
            expandedSource: """
            struct DualConformer: InteractionInvariant, ActionIdempotenceInvariant {
                typealias State = InboxState
                typealias Action = InboxAction
                static let idempotentActions: Set<InboxAction> = []
                static let initialState = InboxState()
                static let reducer: @Sendable (InboxState, InboxAction) -> InboxState = { s, _ in s }
            }

            struct DualConformerInteractionInvariantTests {
                @Test func actionIdempotenceInvariant_DualConformer() async throws {
                        try await checkActionIdempotenceInvariantPropertyLaws(
                            for: DualConformer.self,
                            initialState: DualConformer.initialState,
                            reducer: DualConformer.reducer
                        )
                    }
            }
            """,
            macros: interactionTestsMacros
        )
    }

    @Test func noFamilyConformanceDiagnoses() {
        // A type with no family conformance — for example a plain
        // struct or one conforming to an unrelated protocol — should
        // produce the `noInteractionInvariantConformance` warning and
        // emit no peer test suite.
        assertMacroExpansion(
            """
            @InteractionInvariantTests
            struct PlainStruct: Equatable {
                let value: Int
            }
            """,
            expandedSource: """
            struct PlainStruct: Equatable {
                let value: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@InteractionInvariantTests requires the decoratee "
                        + "to conform to one of the five v2.3.0 family protocols "
                        + "in its primary declaration's inheritance clause: "
                        + "CardinalityInvariant, ReferentialIntegrityInvariant, "
                        + "BiconditionalInvariant, ConservationInvariant, "
                        + "ActionIdempotenceInvariant (or the root "
                        + "InteractionInvariant). Conformances declared via "
                        + "extensions outside the type's primary declaration "
                        + "aren't visible to the macro.",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: interactionTestsMacros
        )
    }
}
