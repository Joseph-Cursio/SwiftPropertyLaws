import Testing
import PropertyBased
@testable import PropertyLawKit

struct EnforcementTests {

    @Test func defaultEnforcementOnlyThrowsOnStrictTier() {
        #expect(EnforcementMode.default.shouldThrow(for: .strict))
        #expect(EnforcementMode.default.shouldThrow(for: .conventional) == false)
        #expect(EnforcementMode.default.shouldThrow(for: .heuristic) == false)
    }

    @Test func strictEnforcementThrowsOnEveryTier() {
        #expect(EnforcementMode.strict.shouldThrow(for: .strict))
        #expect(EnforcementMode.strict.shouldThrow(for: .conventional))
        #expect(EnforcementMode.strict.shouldThrow(for: .heuristic))
    }

    // MARK: - A Conventional violation must be visible, even though it does not throw

    private func failure(tier: StrictnessTier) -> CheckResult {
        CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: tier,
            trials: 100,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: .current,
            outcome: .failed(counterexample: "FileResponse(modifiedAt: 2026-07-13T08:00:00Z)")
        )
    }

    @Test func conventionalViolationUnderDefaultIsRecordedRatherThanSwallowed() throws {
        // The A5 bug. `.default` does not *throw* on a Conventional violation — correct, that is the
        // tier's whole purpose. But not-throwing had been implemented as not-saying-anything, and
        // every `checkXxx…` entry point is `@discardableResult`, so a lossy codec that cannot
        // round-trip its own dates was reported as a pass. Silence was never the tier's meaning;
        // not failing the build was.
        //
        // `withKnownIssue` is the assertion: it *fails* if no issue is recorded inside it, so this
        // passing is proof the violation now speaks.
        withKnownIssue("the Conventional violation must surface as a non-fatal issue") {
            try PropertyLawViolation.throwIfViolations(
                in: [failure(tier: .conventional)],
                enforcement: .default
            )
        }
    }

    @Test func strictViolationUnderDefaultStillThrows() {
        // The tier semantics are untouched: escalation is unchanged, only silence is fixed.
        #expect(throws: PropertyLawViolation.self) {
            try PropertyLawViolation.throwIfViolations(
                in: [failure(tier: .strict)],
                enforcement: .default
            )
        }
    }

    @Test func aStrictViolationIsThrownRatherThanMerelyRecorded() throws {
        // Guards the obvious over-correction: a Strict violation must not be *downgraded* into a
        // non-fatal issue. If it were recorded instead of thrown, this test would fail on the
        // unexpected issue rather than on the missing throw — so it pins both halves.
        do {
            try PropertyLawViolation.throwIfViolations(
                in: [failure(tier: .strict)],
                enforcement: .default
            )
            Issue.record("expected a Strict violation to throw")
        } catch is PropertyLawViolation {
            // Expected, and no non-fatal issue was recorded on the way out.
        }
    }

    @Test func suppressedAndExpectedViolationsStayQuiet() throws {
        // Explicit policy — someone wrote down that this law does not hold, and why. Re-surfacing
        // them would make the suppression mechanism useless (PRD §4.7). No issue may be recorded.
        let suppressed = CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .suppressed(reason: "lossy by design")
        )
        let expected = CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .expectedViolation(reason: "documented", counterexample: "x")
        )

        try PropertyLawViolation.throwIfViolations(in: [suppressed, expected], enforcement: .default)
    }

    @Test func aPassingResultRecordsNothing() throws {
        let passed = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed
        )

        try PropertyLawViolation.throwIfViolations(in: [passed], enforcement: .default)
    }

    @Test func violationFormatterIncludesPRDDisclaimer() {
        let result = CheckResult(
            protocolLaw: "Equatable.symmetry",
            tier: .strict,
            trials: 5,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: .current,
            outcome: .failed(counterexample: "x = 1, y = 2; …")
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("✗"))
        #expect(text.contains("Equatable.symmetry"))
        #expect(text.contains("Strict"))
        #expect(text.contains("Replay with seed:"))
        #expect(text.contains("Empirical evidence, not a proof."))
    }

    // MARK: - M5: near-miss + coverage rendering

    @Test func formatterRendersNearMissesWhenPresent() {
        let result = CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: [
                "field whitespaceField: \" abc\" → \"abc\"",
                "field timestamp: ..."
            ]
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses (2):"))
        #expect(text.contains("field whitespaceField"))
        #expect(text.contains("field timestamp"))
    }

    @Test func formatterRendersEmptyNearMissList() {
        let result = CheckResult(
            protocolLaw: "Codable.roundTripFidelity[JSON]",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: []
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses: none."))
    }

    @Test func formatterOmitsNearMissesWhenNil() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: nil
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses") == false)
    }

    @Test func formatterCapsLongNearMissLists() {
        let result = CheckResult(
            protocolLaw: "X.law",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            nearMisses: (1...8).map { "entry-\($0)" }
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Near-misses (8):"))
        #expect(text.contains("entry-1"))
        #expect(text.contains("entry-5"))
        #expect(text.contains("… 3 more"))
        #expect(text.contains("entry-6") == false)
    }

    @Test func formatterRendersCoverageHintsSorted() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 1_000,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed,
            coverageHints: CoverageHints(
                inputClasses: ["positive": 500, "negative": 488, "zero": 12],
                boundaryHits: ["Int.min": 1, "Int.max": 0]
            )
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Coverage:"))
        // Sorted by key: negative, positive, zero — boundary keys: Int.max, Int.min
        #expect(text.contains("classes={negative: 488, positive: 500, zero: 12}"))
        #expect(text.contains("boundaries={Int.max: 0, Int.min: 1}"))
    }

    @Test func formatterOmitsCoverageWhenNil() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("Coverage:") == false)
    }
}
