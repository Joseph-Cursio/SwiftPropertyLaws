import PropertyBased
@testable import PropertyLawKit
import Testing

struct SuppressionTests {

    // MARK: - LawIdentifier matching

    @Test func matchesPlainQualifiedName() {
        let id = LawIdentifier.equatable(.reflexivity)
        #expect(id.matches("Equatable.reflexivity"))
        #expect(id.matches("Equatable.symmetry") == false)
        #expect(id.matches("Hashable.reflexivity") == false)
    }

    @Test func matchesIgnoresBracketedSuffix() {
        // Codable's law name carries a backend tag like `[JSON]`; suppression
        // must match the bare law name regardless of which codec ran.
        let id = LawIdentifier.codable(.roundTripFidelity)
        #expect(id.matches("Codable.roundTripFidelity[JSON]"))
        #expect(id.matches("Codable.roundTripFidelity[BinaryPlist]"))
        #expect(id.matches("Codable.roundTripFidelity"))
        #expect(id.matches("Codable.somethingElse[JSON]") == false)
    }

    // MARK: - .skip suppresses without paying trial budget

    @Test func skipReturnsSuppressedOutcomeAndZeroTrials() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: AntiReflexiveEquatable.self,
            using: Gen<AntiReflexiveEquatable>.antiReflexive(),
            options: LawCheckOptions(
                budget: .standard,
                suppressions: [
                    .skip(.equatable(.reflexivity), reason: "exercising suppression API")
                ]
            )
        )
        let reflexivity = try #require(results.first { $0.protocolLaw == "Equatable.reflexivity" })
        if case .suppressed(let reason) = reflexivity.outcome {
            #expect(reason == "exercising suppression API")
        } else {
            Issue.record("expected .suppressed outcome; got \(reflexivity.outcome)")
        }
        #expect(reflexivity.trials == 0)
        // Sibling laws still ran.
        let symmetry = try #require(results.first { $0.protocolLaw == "Equatable.symmetry" })
        #expect(symmetry.trials > 0)
    }

    @Test func skipDoesNotThrowEvenWhenLawWouldFail() async throws {
        // Anti-reflexive type would normally throw because Equatable.reflexivity
        // is Strict. Suppression must defuse that.
        let results = try await checkEquatablePropertyLaws(
            for: AntiReflexiveEquatable.self,
            using: Gen<AntiReflexiveEquatable>.antiReflexive(),
            options: LawCheckOptions(
                budget: .sanity,
                suppressions: [
                    .skip(.equatable(.reflexivity), reason: "intentional for test")
                ]
            )
        )
        #expect(results.allSatisfy { !$0.isViolation })
    }

    // MARK: - .intentionalViolation rewrites failure to .expectedViolation

    @Test func intentionalViolationRewritesFailureWithoutThrowing() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: AntiReflexiveEquatable.self,
            using: Gen<AntiReflexiveEquatable>.antiReflexive(),
            options: LawCheckOptions(
                budget: .sanity,
                suppressions: [
                    .intentionalViolation(
                        .equatable(.reflexivity),
                        reason: "anti-reflexive by design"
                    ),
                ]
            )
        )
        let reflexivity = try #require(results.first { $0.protocolLaw == "Equatable.reflexivity" })
        if case let .expectedViolation(reason, counterexample) = reflexivity.outcome {
            #expect(reason == "anti-reflexive by design")
            #expect(counterexample.contains("x == x evaluated to false"))
        } else {
            Issue.record("expected .expectedViolation outcome; got \(reflexivity.outcome)")
        }
        // Trials > 0 because the check actually ran.
        #expect(reflexivity.trials > 0)
        // Not surfaced as a violation; throwIfViolations did not throw.
        #expect(reflexivity.isViolation == false)
    }

    @Test func intentionalViolationOnPassingLawJustPasses() async throws {
        // Conventional behavior: if the law would pass anyway, the result is
        // .passed (no surprise-pass signal in M3 — see PRD §4.7).
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(
                budget: .sanity,
                suppressions: [
                    .intentionalViolation(
                        .equatable(.reflexivity),
                        reason: "should not actually trigger"
                    ),
                ]
            )
        )
        let reflexivity = try #require(results.first { $0.protocolLaw == "Equatable.reflexivity" })
        #expect(reflexivity.outcome == .passed)
    }

    // MARK: - Suppression overrides .strict enforcement escalation

    @Test func skipOnConventionalLawSuppressesStrictEnforcement() async throws {
        // UnstableHasher would throw under enforcement: .strict because
        // stabilityWithinProcess is Conventional. Suppression must defuse.
        let results = try await checkHashablePropertyLaws(
            for: UnstableHasher.self,
            using: Gen<UnstableHasher>.unstableHasher(),
            options: LawCheckOptions(
                budget: .sanity,
                enforcement: .strict,
                suppressions: [
                    .skip(.hashable(.stabilityWithinProcess), reason: "test")
                ]
            ),
            laws: .ownOnly
        )
        let stability = try #require(
            results.first { $0.protocolLaw == "Hashable.stabilityWithinProcess" }
        )
        if case .suppressed = stability.outcome { } else {
            Issue.record("expected .suppressed under .strict enforcement")
        }
    }

    // MARK: - Inherited suite honors caller's suppressions

    @Test func suppressionsPropagateToInheritedEquatableSuite() async throws {
        // Calling checkHashable(.all) on a type whose Equatable.reflexivity is
        // broken — we suppress reflexivity at the Hashable call site and expect
        // the inherited Equatable suite to honor it.
        let results = try await checkHashablePropertyLaws(
            for: ReflexivityBreakingHashable.self,
            using: Gen<ReflexivityBreakingHashable>.reflexivityBreaking(),
            options: LawCheckOptions(
                budget: .sanity,
                suppressions: [
                    .skip(.equatable(.reflexivity), reason: "propagated through inheritance")
                ]
            ),
            laws: .all
        )
        let reflexivity = try #require(
            results.first { $0.protocolLaw == "Equatable.reflexivity" }
        )
        if case .suppressed = reflexivity.outcome { } else {
            Issue.record("inherited suite ignored suppression; got \(reflexivity.outcome)")
        }
    }

    // MARK: - ViolationFormatter renders new outcomes

    @Test func formatterRendersSuppressedOutcome() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 0,
            seed: Seed(stateA: 0, stateB: 0, stateC: 0, stateD: 0),
            environment: .current,
            outcome: .suppressed(reason: "NaN by design")
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("…"))
        #expect(text.contains("Suppressed: NaN by design"))
    }

    @Test func formatterRendersExpectedViolation() {
        let result = CheckResult(
            protocolLaw: "Equatable.reflexivity",
            tier: .strict,
            trials: 7,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: .current,
            outcome: .expectedViolation(
                reason: "anti-reflexive on purpose",
                counterexample: "x = …; x == x evaluated to false"
            )
        )
        let text = ViolationFormatter.format(result)
        #expect(text.contains("⊘"))
        #expect(text.contains("Expected violation: anti-reflexive on purpose"))
        #expect(text.contains("Counterexample:"))
    }
}
