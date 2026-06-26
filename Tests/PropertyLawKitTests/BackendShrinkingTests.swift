import Testing
import PropertyBased
@testable import PropertyLawKit

/// v2.4 — backend shrinking (minimal counterexamples).
///
/// Shrinking is a `PerLawDriver` policy that re-runs the law's own `property`
/// as the failure oracle, so these tests drive the driver directly with a
/// planted-failing `Int` law and an `Int` shrinker. The closure seam
/// (`PropertyBackend`) and `BackendCheckResult` are deliberately untouched by
/// v2.4 — shrinking never threads a `Generator`.
@Suite
struct BackendShrinkingTests {

    /// A LawCheck<Int> whose property fails for values ≥ `threshold`, sampled
    /// from a wide range so the first failure is large, with an integer
    /// shrinker that halves toward zero.
    private func failingIntCheck(
        threshold: Int,
        shrink: (@Sendable (Int) -> [Int])?
    ) -> LawCheck<Int> {
        LawCheck(
            sample: { rng in Int.random(in: 0...1_000_000, using: &rng) },
            property: { value in value < threshold },
            formatCounterexample: { value, _ in "\(value)" },
            shrink: shrink
        )
    }

    /// `Int.shrink(towards: 0)` from swift-property-based, surfaced as `[Int]`.
    private let halveTowardZero: @Sendable (Int) -> [Int] = { Array($0.shrink(towards: 0)) }

    private func run(_ check: LawCheck<Int>, options: LawCheckOptions) async -> CheckResult {
        await PerLawDriver.run(
            protocolLaw: "Test.failsAboveThreshold",
            tier: .strict,
            options: options,
            check: check
        )
    }

    @Test
    func shrinkingReducesToASmallerStillFailingInput() async throws {
        // Force a failure by setting a tiny budget that still samples large
        // ints; threshold 1000 fails on almost every draw from 0...1_000_000.
        let result = await run(
            failingIntCheck(threshold: 1000, shrink: halveTowardZero),
            options: LawCheckOptions(budget: .standard)
        )

        #expect(result.isViolation)
        #expect(result.shrinkSteps > 0)
        let shrunkFrom = try #require(result.shrunkFrom)
        let minimalString = try #require(result.counterexample)
        let original = Int(shrunkFrom)
        let minimal = Int(minimalString)
        #expect(original != nil)
        #expect(minimal != nil)

        // The minimal value still fails (≥ threshold) and is no larger than
        // the original first-failing value.
        if let original, let minimal {
            #expect(minimal >= 1000)
            #expect(minimal <= original)
        }
    }

    @Test
    func noShrinkerReportsFirstFailingInputVerbatim() async throws {
        let result = await run(
            failingIntCheck(threshold: 1000, shrink: nil),
            options: LawCheckOptions(budget: .standard)
        )

        #expect(result.isViolation)
        #expect(result.shrinkSteps == 0)
        #expect(result.shrunkFrom == nil)
        // Counterexample is the raw first failing value — behavior identical
        // to pre-v2.4.
        let raw = try #require(result.counterexample)
        let value = Int(raw)
        #expect(value != nil)
        #expect((value ?? 0) >= 1000)
    }

    @Test
    func shrinkingIsDeterministicUnderAFixedSeed() async throws {
        // First run draws a fresh seed and reports it back.
        let first = await run(
            failingIntCheck(threshold: 1000, shrink: halveTowardZero),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(first.isViolation)

        // Replaying that exact seed reproduces the same minimal counterexample
        // and the same step count — shrinking is a pure function of the
        // (reproduced) first failing input.
        let replay = await run(
            failingIntCheck(threshold: 1000, shrink: halveTowardZero),
            options: LawCheckOptions(budget: .standard, seed: first.seed)
        )
        #expect(replay.counterexample == first.counterexample)
        #expect(replay.shrunkFrom == first.shrunkFrom)
        #expect(replay.shrinkSteps == first.shrinkSteps)
    }

    @Test
    func ternaryLawShrinksEachComponentTowardZero() async throws {
        // A triple law that fails when the sum is large; each component shrinks
        // toward zero. Exercises the `runTernaryLaw` tuple-lifting path.
        let result = await runTernaryLaw(
            "Test.tripleSumBelowThreshold",
            generator: Gen<Int>.int(in: 0...1_000_000),
            options: LawCheckOptions(budget: .standard),
            property: { first, second, third in first + second + third < 3000 },
            formatCounterexample: { first, second, third, _ in "\(first),\(second),\(third)" },
            shrink: { Array($0.shrink(towards: 0)) }
        )

        #expect(result.isViolation)
        #expect(result.shrinkSteps > 0)
        #expect(result.shrunkFrom != nil)

        // The minimal triple still fails (sum ≥ 3000) and its sum is no larger
        // than the original failing triple's sum.
        let minimal = try #require(result.counterexample)
        let parts = minimal.split(separator: ",").map { Int($0) }
        #expect(parts.allSatisfy { $0 != nil })
        let sum = parts.compactMap { $0 }.reduce(0, +)
        #expect(sum >= 3000)
    }

    @Test
    func equatableSuiteThreadsAShrinkerEndToEnd() async throws {
        // A deliberately broken Equatable whose `==` is non-reflexive above a
        // threshold, exercised through the public suite with an Int-backed
        // shrinker to prove the public path wires shrinking through. The Strict
        // reflexivity violation throws under `.default` enforcement, so we
        // catch it and inspect the carried results.
        do {
            _ = try await checkEquatablePropertyLaws(
                for: BrokenAboveThreshold.self,
                using: Gen<Int>.int(in: 0...1_000_000).map(BrokenAboveThreshold.init),
                options: LawCheckOptions(budget: .standard, enforcement: .default),
                shrink: { value in value.raw.shrink(towards: 0).map(BrokenAboveThreshold.init) }
            )
            Issue.record("expected the broken Equatable to throw a PropertyLawViolation")
        } catch let violation as PropertyLawViolation {
            let reflexivity = try #require(
                violation.results.first { $0.protocolLaw == "Equatable.reflexivity" }
            )
            #expect(reflexivity.isViolation)
            #expect(reflexivity.shrinkSteps > 0)
            // The shrinker drove the counterexample down to the threshold.
            #expect(reflexivity.counterexample?.contains("raw: 1000") == true)
        }
    }
}

/// Planted bug: reflexivity (`x == x`) fails once `raw >= 1000`.
private struct BrokenAboveThreshold: Equatable, Sendable {
    let raw: Int
    init(_ raw: Int) { self.raw = raw }
    static func == (lhs: BrokenAboveThreshold, rhs: BrokenAboveThreshold) -> Bool {
        if lhs.raw >= 1000 && rhs.raw >= 1000 { return false }   // breaks reflexivity
        return lhs.raw == rhs.raw
    }
}
