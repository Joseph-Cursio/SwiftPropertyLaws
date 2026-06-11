import Testing
import PropertyBased
@testable import PropertyLawKit

// StatefulGuard conformance fixtures are scoped inside the @Suite struct,
// nesting them one level deeper than the rule's default — idiomatic for
// Swift Testing fixtures.
// swiftlint:disable nesting

// v2.2.0 — ActionSequenceFactory: primary entry consumed by
// SwiftInferProperties v2.0 M2 / M3 for synthesizing action sequences
// for interaction-invariant verify. The convenience CaseIterable entry
// is tested separately (M2.B).

@Suite("ActionSequenceFactory — v2.2.0 primary entry + applyGuards")
struct ActionSequenceFactoryTests {

    enum TestAction: CaseIterable, Sendable, Equatable {
        case foo, bar, baz
    }

    /// `wouldAllow(_:given:) = true` always. The factory should
    /// short-circuit when guards is empty, but when guards is
    /// non-empty-but-permissive the behavior must be unchanged.
    struct AlwaysAllow: StatefulGuard {
        typealias Action = TestAction
        func wouldAllow(_ next: TestAction, given history: [TestAction]) -> Bool { true }
    }

    /// `wouldAllow(_:given:) = false` always.
    struct AlwaysDeny: StatefulGuard {
        typealias Action = TestAction
        func wouldAllow(_ next: TestAction, given history: [TestAction]) -> Bool { false }
    }

    /// Disallows repeating the immediately-previous action (a
    /// realistic shape of stateful guard).
    struct NoRepeat: StatefulGuard {
        typealias Action = TestAction
        func wouldAllow(_ next: TestAction, given history: [TestAction]) -> Bool {
            history.last != next
        }
    }

    /// Disallows `.bar` entirely (regardless of history).
    struct ForbidBar: StatefulGuard {
        typealias Action = TestAction
        func wouldAllow(_ next: TestAction, given history: [TestAction]) -> Bool {
            next != .bar
        }
    }

    private func makeRNG() -> Xoshiro {
        Xoshiro(seed: (0xAA, 0xBB, 0xCC, 0xDD))
    }

    // MARK: - applyGuards (pure helper)

    @Test("applyGuards with empty guards preserves the candidate sequence")
    func applyGuardsEmpty() {
        let candidates: [TestAction] = [.foo, .bar, .baz, .foo]
        let result = ActionSequenceFactory.applyGuards(candidates, statefulGuards: [])
        #expect(result == candidates)
    }

    @Test("applyGuards with .allowAll preserves the sequence — non-empty-but-permissive")
    func applyGuardsAllowAll() {
        let candidates: [TestAction] = [.foo, .bar, .baz]
        let result = ActionSequenceFactory.applyGuards(
            candidates, statefulGuards: [AlwaysAllow()]
        )
        #expect(result == candidates)
    }

    @Test("applyGuards with .denyAll yields empty sequence")
    func applyGuardsDenyAll() {
        let candidates: [TestAction] = [.foo, .bar, .baz, .foo]
        let result = ActionSequenceFactory.applyGuards(
            candidates, statefulGuards: [AlwaysDeny()]
        )
        #expect(result.isEmpty)
    }

    @Test("applyGuards .noRepeat drops consecutive duplicates")
    func applyGuardsNoRepeat() {
        let candidates: [TestAction] = [.foo, .foo, .bar, .bar, .baz, .baz]
        let result = ActionSequenceFactory.applyGuards(
            candidates, statefulGuards: [NoRepeat()]
        )
        // Each .foo / .bar / .baz is accepted on first appearance; the
        // duplicate immediately following is rejected.
        #expect(result == [.foo, .bar, .baz])
    }

    @Test("applyGuards composes multiple guards — all must accept (AND semantics)")
    func applyGuardsCompose() {
        let candidates: [TestAction] = [.foo, .bar, .baz, .foo, .bar]
        let result = ActionSequenceFactory.applyGuards(
            candidates, statefulGuards: [NoRepeat(), ForbidBar()]
        )
        // .bar is removed entirely; remaining .foo and .baz are kept;
        // the trailing .foo passes (it's not a repeat — .baz was last
        // accepted).
        #expect(result == [.foo, .baz, .foo])
    }

    @Test("applyGuards history reflects accepted (not candidate) actions")
    func applyGuardsHistoryIsAccepted() {
        // .bar is rejected; the .foo that follows is *not* a repeat of
        // an accepted action (the .foo is the last accepted before
        // .bar was offered) — so the second .foo IS a repeat and is
        // dropped.
        let candidates: [TestAction] = [.foo, .bar, .foo]
        let result = ActionSequenceFactory.applyGuards(
            candidates, statefulGuards: [NoRepeat(), ForbidBar()]
        )
        #expect(result == [.foo])
    }

    // MARK: - actionSequence(from:) primary entry

    @Test("primary entry with empty guards generates an array of `length`-bounded size")
    func primaryEntryEmptyGuardsDelegatesToArrayOf() {
        let gen = ActionSequenceFactory.actionSequence(
            from: Gen<TestAction>.case,
            length: 5...5
        )
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(result.count == 5)
    }

    @Test("primary entry default length is 0...16")
    func primaryEntryDefaultLength() {
        #expect(ActionSequenceFactory.defaultLength == 0...16)
        let gen = ActionSequenceFactory.actionSequence(from: Gen<TestAction>.case)
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(result.count >= 0)
        #expect(result.count <= 16)
    }

    @Test("primary entry with .denyAll guard yields an empty sequence")
    func primaryEntryDenyAllYieldsEmpty() {
        let gen = ActionSequenceFactory.actionSequence(
            from: Gen<TestAction>.case,
            length: 10...10,
            statefulGuards: [AlwaysDeny()]
        )
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(result.isEmpty)
    }

    @Test("primary entry threads guards through every generated candidate")
    func primaryEntryThreadsGuards() {
        let gen = ActionSequenceFactory.actionSequence(
            from: Gen<TestAction>.case,
            length: 20...20,
            statefulGuards: [ForbidBar()]
        )
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(!result.contains(.bar))
        // Total length must be ≤ 20 (candidates draw is exactly 20;
        // .bar candidates are dropped).
        #expect(result.count <= 20)
    }

    @Test("primary entry result length is ≤ requested length under restrictive guards")
    func primaryEntryShorterUnderRestrictiveGuards() {
        let gen = ActionSequenceFactory.actionSequence(
            from: Gen<TestAction>.case,
            length: 16...16,
            statefulGuards: [NoRepeat()]
        )
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(result.count <= 16)
        // No two consecutive actions are equal.
        for index in result.indices.dropFirst() {
            #expect(result[index] != result[index - 1])
        }
    }

    // MARK: - StatefulGuard shape

    @Test("StatefulGuard's Action associatedtype is Sendable-constrained")
    func statefulGuardActionIsSendable() {
        // Compile-time-only check: a conformer with a non-Sendable
        // Action would fail to compile. This test exists so the
        // contract is documented in the test suite.
        let guards: [any StatefulGuard<TestAction>] = [
            AlwaysAllow(), AlwaysDeny(), NoRepeat(), ForbidBar()
        ]
        #expect(guards.count == 4)
    }

    // MARK: - Convenience entry (CaseIterable)

    @Test("convenience entry delegates to the primary entry via Gen<Action>.case")
    func convenienceEntryWorks() {
        let gen = ActionSequenceFactory.actionSequence(
            forCaseIterable: TestAction.self,
            length: 8...8
        )
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(result.count == 8)
        // Every element must be a valid TestAction case.
        for action in result {
            #expect(TestAction.allCases.contains(action))
        }
    }

    @Test("convenience entry honors the default length when not specified")
    func convenienceEntryDefaultLength() {
        let gen = ActionSequenceFactory.actionSequence(forCaseIterable: TestAction.self)
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(result.count >= 0)
        #expect(result.count <= 16)
    }

    @Test("convenience entry threads stateful guards through")
    func convenienceEntryWithGuards() {
        let gen = ActionSequenceFactory.actionSequence(
            forCaseIterable: TestAction.self,
            length: 20...20,
            statefulGuards: [ForbidBar()]
        )
        var rng = makeRNG()
        let result = gen.run(using: &rng)
        #expect(!result.contains(.bar))
    }
}

// swiftlint:enable nesting
