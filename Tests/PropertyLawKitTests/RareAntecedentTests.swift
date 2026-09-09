import Foundation
import PropertyBased
import Testing
@testable import PropertyLawKit

/// **The conditional laws, and the antecedent that a realistic generator does
/// not reach.**
///
/// `Equatable.transitivity` says nothing until three drawn values satisfy
/// `x == y && y == z`. `Hashable.equalityConsistency` says nothing until two
/// satisfy `x == y`. Neither counts how often that happened, so a run that never
/// reached the case reports a pass it has not earned — silently, with no
/// diagnostic anywhere.
@Suite("Rare antecedents in the conditional equality laws")
struct RareAntecedentTests {

    /// `==` is "within 1", which is reflexive and symmetric and **not
    /// transitive**: `0 == 1` and `1 == 2`, but `0 != 2`. A real bug shape, and
    /// the kit's own planted-bug suite drives it with a hand-narrowed `0...3`.
    private struct Rounding: Equatable, Sendable, CustomStringConvertible {
        let raw: Int
        static func == (lhs: Rounding, rhs: Rounding) -> Bool { abs(lhs.raw - rhs.raw) <= 1 }
        var description: String { "R(\(raw))" }
    }

    private func carrier(upTo bound: Int) -> Enumeration<Rounding> {
        Every.elements("r", in: (0 ... bound).map { Rounding(raw: $0) })
    }

    private func sampledCatchesViolation(bound: Int, seed: UInt64) async -> Bool {
        let generator = Gen<Int>.int(in: 0 ... bound).map { Rounding(raw: $0) }
        do {
            _ = try await checkEquatablePropertyLaws(
                using: generator,
                options: LawCheckOptions(
                    budget: .standard,
                    seed: Seed(stateA: seed &+ 1, stateB: 2, stateC: 3, stateD: 4)
                )
            )
            return false
        } catch {
            return true
        }
    }

    /// **The measurement this whole entry point exists for.** A genuinely
    /// non-transitive `==` is caught reliably from a narrow domain and not at all
    /// from an ordinary one — and `0...200` is the generator someone would
    /// actually write.
    @Test func aWideGeneratorMissesAGenuinelyBrokenEquatable() async {
        var narrow = 0
        var wide = 0
        for seed in UInt64(0) ..< 20 {
            if await sampledCatchesViolation(bound: 3, seed: seed) { narrow += 1 }
            if await sampledCatchesViolation(bound: 200, seed: seed) { wide += 1 }
        }
        #expect(narrow == 20, "the hand-narrowed domain catches it on every seed")
        #expect(wide == 0, "and the realistic one catches it on none")
    }

    /// The same type, the same laws, walked. The carrier is the choice a narrow
    /// generator was making silently, and now the result reports it.
    @Test func walkingTheCarrierCatchesItAtEveryWidth() async {
        for bound in [10, 50, 200] {
            var caught = false
            do {
                _ = try await checkEquatablePropertyLaws(overEvery: carrier(upTo: bound))
            } catch is PropertyLawViolation {
                caught = true
            } catch {}
            #expect(caught, "the walk missed the violation at 0...\(bound)")
        }
    }

    /// And it is *cheaper*, which is the counterintuitive part. Smallest-first
    /// ordering reaches `R(0), R(1), R(2)` almost immediately, so the walk stops
    /// long before it would have to consider eight million triples.
    @Test func theWalkStopsEarlyBecauseTheWitnessIsSmall() async {
        var reported: CheckResult?
        do {
            _ = try await checkEquatablePropertyLaws(overEvery: carrier(upTo: 200))
        } catch let violation as PropertyLawViolation {
            reported = violation.results.first { $0.protocolLaw == "Equatable.transitivity" }
        } catch {}
        let result = try? #require(reported)
        #expect(result?.counterexample?.contains("R(0)") == true)
        // 201 values means 8 120 601 triples exist; the walk examines a handful.
        #expect(result?.coverage?.spaceSize == 8_120_601)
        #expect((result?.trials ?? .max) < 1_000,
                "the witness is small, so the walk should stop almost immediately")
    }

    /// A correct `Equatable` clears the whole carrier, and says so.
    @Test func aCorrectEquatableClearsTheCarrier() async throws {
        let results = try await checkEquatablePropertyLaws(
            overEvery: Every.elements("n", in: 0 ..< 12))
        #expect(results.allSatisfy { !$0.isViolation })
        #expect(results.allSatisfy { $0.coverage?.isComplete == true })
    }

    /// The one place a walked suite checks less than its sampled twin, pinned so
    /// it stays a decision rather than a drift.
    @Test func walkedHashableOmitsOnlyTheDistributionLaw() async throws {
        let carrier = Every.elements("n", in: 0 ..< 12)
        let walked = try await checkHashablePropertyLaws(overEvery: carrier)
        let sampled = try await checkHashablePropertyLaws(
            using: Gen<Int>.int(in: 0 ..< 12), options: LawCheckOptions(budget: .sanity))

        let walkedLaws = Set(walked.map(\.protocolLaw))
        let sampledLaws = Set(sampled.map(\.protocolLaw))
        #expect(sampledLaws.subtracting(walkedLaws) == ["Hashable.distribution"])
        #expect(walkedLaws.subtracting(sampledLaws).isEmpty)
        #expect(walkedLaws.contains("Hashable.equalityConsistency"))
        #expect(walkedLaws.contains("Equatable.transitivity"), "the inherited chain is walked too")
    }
}
