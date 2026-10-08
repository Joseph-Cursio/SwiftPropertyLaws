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

    // MARK: - A sub-Strict violation must be visible, without failing the test

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

    @Test(arguments: [StrictnessTier.conventional, .heuristic])
    func subStrictViolationUnderDefaultIsAWarningNotAFailure(tier: StrictnessTier) async throws {
        // The A5 bug. `.default` does not *throw* on a Conventional violation — correct, that is the
        // tier's whole purpose. But not-throwing had been implemented as not-saying-anything, and
        // every `checkXxx…` entry point is `@discardableResult`, so a lossy codec that cannot
        // round-trip its own dates was reported as a pass. Silence was never the tier's meaning;
        // not failing the build was.
        //
        // And the fix for silence was itself half wrong: it recorded at `Issue.record`'s default
        // `.error` severity, which marks the test failed. This test used to assert with a bare
        // `withKnownIssue`, which absorbs an error as readily as a warning, so it passed either way.
        // `recordedWarnings` collects warnings only — an error-severity issue fails this test, and
        // so does silence, because then the count is zero.
        let warnings = try await recordedWarnings {
            try PropertyLawViolation.throwIfViolations(in: [failure(tier: tier)], enforcement: .default)
        }
        #expect(lawsReported(in: warnings) == ["Codable.roundTripFidelity[JSON]"])
        #expect(warnings.first?.contains("\(tier.rawValue) tier") == true)
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

    @Test func aStrictViolationIsThrownRatherThanMerelyRecorded() async throws {
        // Guards the obvious over-correction: a Strict violation must not be *downgraded* into a
        // warning, nor reported twice — thrown *and* recorded. A recorded warning does not fail a
        // test, so the second half needs the explicit empty-count assertion; the missing throw
        // fails on its own.
        let warnings = try await recordedWarnings {
            do {
                try PropertyLawViolation.throwIfViolations(
                    in: [failure(tier: .strict)],
                    enforcement: .default
                )
                Issue.record("expected a Strict violation to throw")
            } catch is PropertyLawViolation {
                // Expected.
            }
        }
        #expect(warnings.isEmpty, "a thrown Strict violation was also recorded: \(warnings)")
    }

    @Test func suppressedAndExpectedViolationsStayQuiet() async throws {
        // Explicit policy — someone wrote down that this law does not hold, and why. Re-surfacing
        // them would make the suppression mechanism useless (PRD §4.7). No issue may be recorded —
        // and since a warning would not fail this test, that is asserted rather than assumed.
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

        let warnings = try await recordedWarnings {
            try PropertyLawViolation.throwIfViolations(in: [suppressed, expected], enforcement: .default)
        }
        #expect(warnings.isEmpty, "explicit policy was re-surfaced: \(warnings)")
    }

    @Test func aPassingResultRecordsNothing() async throws {
        let passed = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .conventional,
            trials: 100,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .passed
        )

        let warnings = try await recordedWarnings {
            try PropertyLawViolation.throwIfViolations(in: [passed], enforcement: .default)
        }
        #expect(warnings.isEmpty, "a passing result was reported: \(warnings)")
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
