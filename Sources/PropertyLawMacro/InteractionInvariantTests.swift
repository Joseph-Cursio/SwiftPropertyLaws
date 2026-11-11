/// v2.5.0 — peer macro that attaches to an `InteractionInvariant`
/// conformer and emits a sibling `<TypeName>InteractionInvariantTests`
/// `@Suite` struct with a single `@Test func` that calls the
/// appropriate v2.4.0 harness against the conformer's required
/// `initialState` + `reducer` members.
///
/// **Family detection.** The emit shape depends on which of the
/// five family sub-protocols the conformer extends:
///
/// - `CardinalityInvariant` / `ReferentialIntegrityInvariant` /
///   `BiconditionalInvariant` / `ConservationInvariant` — calls
///   `checkInteractionInvariantPropertyLaws`.
/// - `ActionIdempotenceInvariant` — calls
///   `checkActionIdempotenceInvariantPropertyLaws`.
///
/// **Required members on the conformer.** The macro emits
/// references to `Self.initialState` and `Self.reducer` — the user
/// must define both. A missing member surfaces as a clear compile
/// error from the emitted test code, matching `@PropertyLawSuite`'s
/// "missing `gen()`" posture (PRD §9.4 / PRD §5.7's "compile
/// error beats silent fallthrough").
///
/// ```swift
/// @InteractionInvariantTests
/// struct InboxCardinality: CardinalityInvariant {
///     typealias State = Inbox.State
///     static let initialState = Inbox.State()
///     static let reducer: @Sendable (Inbox.State, Inbox.Action) -> Inbox.State = Inbox.reduce
///     static func invariantHolds(in state: Inbox.State) -> Bool {
///         (state.isShowingSheet ? 1 : 0) + (state.isShowingAlert ? 1 : 0) <= 1
///     }
/// }
/// ```
///
/// Expands (as a peer of `InboxCardinality`) to:
/// ```swift
/// struct InboxCardinalityInteractionInvariantTests {
///     @Test func invariantHoldsAfterEachStep_InboxCardinality() async throws {
///         try await checkInteractionInvariantPropertyLaws(
///             for: InboxCardinality.self,
///             initialState: InboxCardinality.initialState,
///             reducer: InboxCardinality.reducer
///         )
///     }
/// }
/// ```
@attached(peer, names: suffixed(InteractionInvariantTests))
// swiftlint:disable:next unused_declaration - public macro; clients apply it as an attribute
public macro InteractionInvariantTests() = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "InteractionInvariantTestsMacro"
)
