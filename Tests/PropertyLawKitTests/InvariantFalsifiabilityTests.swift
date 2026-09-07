import PropertyBased
@testable import PropertyLawKit
import Testing

@Suite("Invariant falsifiability")
struct InvariantFalsifiabilityTests {

    /// A selection that must refer to an item that exists — a real constraint.
    private struct AppState: Sendable {
        var items: [Int]
        var selected: Int?
    }

    private enum SelectionIntegrity: InteractionInvariant, Sendable {
        static func invariantHolds(in state: AppState) -> Bool {
            guard let selected = state.selected else { return true }
            return state.items.contains(selected)
        }
    }

    /// The §20.4.2 shape: a predicate that lost the field it used to read.
    private enum VacuousInvariant: InteractionInvariant, Sendable {
        static func invariantHolds(in state: AppState) -> Bool {
            state.items.count >= 0   // always true; forbids nothing
        }
    }

    private enum Action: CaseIterable, Sendable { case addItem, clearSelection }

    private static func stateGen() -> Generator<AppState, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0 ... 5).array(of: 0 ... 4),
            Gen<Int?>.frequency((1, Gen.always(nil)), (3, Gen<Int>.int(in: 0 ... 9).map { .some($0) }))
        ).map { AppState(items: $0, selected: $1) }
    }

    @Test("A real invariant rejects some generated state")
    func realInvariantIsFalsifiable() async throws {
        let results = try await checkInvariantIsFalsifiable(
            for: SelectionIntegrity.self,
            using: Self.stateGen(),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    /// The law is Conventional, so a violation is *reported* rather than thrown.
    /// `withKnownIssue` fails if nothing is recorded, so this test passing IS the assertion
    /// that a vacuous invariant speaks up — the same shape `CodableLawsTests` uses for the
    /// lossy codec.
    @Test("An invariant that forbids nothing is reported")
    func vacuousInvariantIsCaught() async throws {
        var captured: [CheckResult] = []
        await withKnownIssue("a vacuous invariant must surface, even though it does not fail the build") {
            captured = try await checkInvariantIsFalsifiable(
                for: VacuousInvariant.self,
                using: Self.stateGen(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let result = try #require(captured.first)
        #expect(result.protocolLaw == "InteractionInvariant.isFalsifiable")
        #expect(result.tier == .conventional)
        guard case let .failed(counterexample) = result.outcome else {
            Issue.record("expected a reported violation, got \(result.outcome)")
            return
        }
        #expect(counterexample.contains("forbids nothing"))
    }

    /// The reason this law exists. A vacuous invariant satisfies the sequence-level law on every
    /// action sequence, because the thing being enforced is `true` — so the suite goes green and
    /// the reader believes a property is under test.
    @Test("The existing sequence law passes a vacuous invariant, which is the problem")
    func vacuousInvariantPassesTheSequenceLaw() async throws {
        let results = try await checkInteractionInvariantPropertyLaws(
            for: VacuousInvariant.self,
            initialState: AppState(items: [], selected: nil),
            reducer: { (state: AppState, action: Action) -> AppState in
                var next = state
                switch action {
                case .addItem: next.items.append(next.items.count)
                case .clearSelection: next.selected = nil
                }
                return next
            },
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
