import Foundation
import PropertyBased
import Testing
@testable import PropertyLawKit

/// **`EqualValuePairing.everyPairOfDraws`: the equal pairs a budget already
/// contains.** The three laws that need equal values pass without testing
/// anything when a trial's independent draws differ, which over a wide generator
/// is nearly always. Comparing every draw with every other finds the birthday
/// collisions instead. The fixtures are `RareAntecedentTests`', so the two files
/// measure the same bugs.
@Suite("Pooling the draws of the laws that need equal values")
struct EqualValuePairingTests {

    typealias DollarMoney = RareAntecedentTests.DollarMoney
    typealias AbsoluteOrder = RareAntecedentTests.AbsoluteOrder
    typealias Rounding = RareAntecedentTests.Rounding

    private static func options(
        _ pairing: EqualValuePairing, seed index: UInt64, budget: TrialBudget = .standard
    ) -> LawCheckOptions {
        LawCheckOptions(budget: budget, seed: RareAntecedentTests.mixedSeed(index), equalValuePairing: pairing)
    }

    /// Of `seeds` well-mixed seeds, how many runs threw.
    private func seedsCaught(
        _ pairing: EqualValuePairing, seeds: Int = 20, _ run: (LawCheckOptions) async throws -> Void
    ) async -> Int {
        var caught = 0
        for index in 0 ..< UInt64(seeds) {
            do {
                try await run(Self.options(pairing, seed: index))
            } catch is PropertyLawViolation {
                caught += 1
            } catch {}
        }
        return caught
    }

    // MARK: - What it catches

    /// The README's dollar bug at ±1 000 000. Independent pairs catch it in about
    /// 7 runs of 100; 499 500 pairs from the same 1 000 draws contain ~25 that
    /// share a dollar, and every seed finds one.
    @Test func everyPairCatchesTheDollarBugAtAWideRange() async {
        let generator = Gen<Int>.int(in: -1_000_000 ... 1_000_000).map(DollarMoney.init(cents:))
        func caught(_ pairing: EqualValuePairing) async -> Int {
            await seedsCaught(pairing) { options in
                _ = try await checkHashablePropertyLaws(using: generator, options: options, laws: .ownOnly)
            }
        }
        #expect(await caught(.everyPairOfDraws) == 20)
        #expect(await caught(.independent) <= 5, "the default should still mostly miss it")
    }

    /// The `abs` ordering at ±10 000: two draws share an absolute value about once
    /// in 10 000 pairs, so 1 000 independent pairs mostly miss it and 499 500
    /// pooled pairs do not.
    @Test func everyPairCatchesTheAbsoluteOrdering() async {
        let generator = Gen<Int>.int(in: -10_000 ... 10_000).map(AbsoluteOrder.init(cents:))
        func caught(_ pairing: EqualValuePairing) async -> Int {
            await seedsCaught(pairing) { options in
                _ = try await checkComparablePropertyLaws(using: generator, options: options, laws: .ownOnly)
            }
        }
        #expect(await caught(.everyPairOfDraws) == 20)
        #expect(await caught(.independent) <= 5)
    }

    /// A non-transitive "within 1" `==` at ±10 000. Independent triples never
    /// chain; the pool's links form chains, and most seeds reach one that spans
    /// two — the refuting configuration, not merely the antecedent.
    @Test func everyPairFollowsLinksIntoChains() async {
        let generator = Gen<Int>.int(in: -10_000 ... 10_000).map(Rounding.init(raw:))
        func caught(_ pairing: EqualValuePairing) async -> Int {
            await seedsCaught(pairing) { options in
                _ = try await checkEquatablePropertyLaws(using: generator, options: options)
            }
        }
        #expect(await caught(.everyPairOfDraws) >= 12, "most seeds reach a refuting chain")
        #expect(await caught(.independent) == 0)
    }

    /// The failure names the law that needs equal values, and only that law.
    @Test func thePooledFailureIsTheConditionalLaws() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).map(DollarMoney.init(cents:)),
                options: Self.options(.everyPairOfDraws, seed: 0),
                laws: .ownOnly)
        }
        let failed = violation?.results.filter(\.isViolation).map(\.protocolLaw)
        #expect(failed == ["Hashable.equalityConsistency"])
    }

    // MARK: - What it leaves alone

    /// The default draws independently, exactly as before, and says so by
    /// carrying no pool.
    @Test func theDefaultDoesNotPool() async throws {
        #expect(LawCheckOptions().equalValuePairing == .independent)
        let results = try await checkComparablePropertyLaws(
            using: Gen<Int>.int(in: 0 ... 100), options: LawCheckOptions(budget: .sanity))
        #expect(results.allSatisfy { $0.pairedDraws == nil })
    }

    /// Only the three laws pool. `Comparable.transitivity` is conditional too, but
    /// its antecedent is an ordering rather than an equality and fires on a sixth
    /// of all triples, so it has nothing to gain and stays per-trial.
    @Test func onlyTheThreeLawsThatNeedEqualValuesPool() async throws {
        let options = LawCheckOptions(budget: .sanity, equalValuePairing: .everyPairOfDraws)
        let hashable = try await checkHashablePropertyLaws(using: Gen<Int>.int(in: 0 ... 100), options: options)
        let comparable = try await checkComparablePropertyLaws(using: Gen<Int>.int(in: 0 ... 100), options: options)
        let pooled = Set((hashable + comparable).filter { $0.pairedDraws != nil }.map(\.protocolLaw))
        #expect(pooled == ["Hashable.equalityConsistency", "Equatable.transitivity", "Comparable.antisymmetry"])
    }

    /// A walk reaches every pair by construction, so pooling has nothing to add
    /// and the walked entries ignore the setting.
    @Test func aWalkIgnoresThePairing() async throws {
        let results = try await checkHashablePropertyLaws(
            overEvery: Every.elements("n", in: 0 ..< 8),
            options: LawCheckOptions(equalValuePairing: .everyPairOfDraws))
        #expect(results.allSatisfy { $0.pairedDraws == nil })
        #expect(results.allSatisfy { $0.coverage?.isComplete == true })
    }

    // MARK: - What it reports

    /// `trials` counts draws when pooled, and the pool reports the pairs it
    /// compared — `n(n-1)/2` for every pair, fewer through a window.
    @Test func thePoolReportsDrawsAndPairs() async throws {
        let generator = Gen<Int>.int(in: 0 ... 1_000_000)
        func equalityConsistency(_ pairing: EqualValuePairing) async throws -> CheckResult {
            let results = try await checkHashablePropertyLaws(
                using: generator, options: LawCheckOptions(budget: .sanity, equalValuePairing: pairing),
                laws: .ownOnly)
            return try #require(results.first { $0.protocolLaw == "Hashable.equalityConsistency" })
        }
        let everyPair = try await equalityConsistency(.everyPairOfDraws)
        #expect(everyPair.trials == 100)
        #expect(everyPair.pairedDraws == PairedDraws(draws: 100, pairs: 4_950))

        // Each draw against at most the 32 before it: 0 + 1 + … + 31, then 32 each.
        let windowed = try await equalityConsistency(.recentDraws(window: 32))
        #expect(windowed.pairedDraws == PairedDraws(draws: 100, pairs: 496 + 68 * 32))
    }

    /// The count is among pairs, so it can exceed the draws: over four values
    /// about a quarter of 4 950 pairs are equal.
    @Test func applicationsCountPairsNotTrials() async throws {
        let results = try await checkComparablePropertyLaws(
            using: Gen<Int>.int(in: 0 ... 3),
            options: LawCheckOptions(budget: .sanity, equalValuePairing: .everyPairOfDraws),
            laws: .ownOnly)
        let law = try #require(results.first { $0.protocolLaw == "Comparable.antisymmetry" })
        #expect((law.applications ?? 0) > 1_000, "got \(law.applications ?? -1)")
    }

    @Test func theFormatterSaysThePoolAndCountsAmongPairs() {
        let result = CheckResult(
            protocolLaw: "Hashable.equalityConsistency",
            tier: .strict,
            trials: 1_000,
            seed: Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
            environment: Environment.current(backend: SwiftPropertyBasedBackend()),
            outcome: .passed,
            applications: 25,
            pairedDraws: PairedDraws(draws: 1_000, pairs: 499_500))
        let rendered = ViolationFormatter.format(result)
        #expect(rendered.contains("[Strict, 1000 draws, 499500 pairs compared]"))
        #expect(rendered.contains("Applied: 25 times among 499500 pairs."))
        #expect(rendered.contains("Replay with seed:"), "the pool is one seeded stream, so the seed replays it")
    }

    // MARK: - Replay and shrinking

    /// The pool is a prefix of one seeded stream, and the run stops at the draw
    /// that completed the refuting pair — so the same seed meets the same pair at
    /// the same draw.
    @Test func theSeedReplaysThePool() async throws {
        func failing() async throws -> CheckResult {
            let violation = await #expect(throws: PropertyLawViolation.self) {
                try await checkHashablePropertyLaws(
                    using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).map(DollarMoney.init(cents:)),
                    options: Self.options(.everyPairOfDraws, seed: 3),
                    laws: .ownOnly)
            }
            let failure = violation?.results.first { $0.isViolation }
            return try #require(failure)
        }
        let first = try await failing()
        let second = try await failing()
        #expect(first.counterexample == second.counterexample)
        #expect(first.pairedDraws == second.pairedDraws)
        let pooled = try #require(first.pairedDraws)
        #expect(pooled.draws < 1_000, "the run stops at the draw that completed the pair")
        #expect(first.trials == pooled.draws)
        // Every pair of the draws before the last, then part of the last draw's row.
        let before = (pooled.draws - 1) * (pooled.draws - 2) / 2
        #expect((before + 1 ... before + pooled.draws - 1).contains(pooled.pairs))
    }

    // MARK: - The chain walk, driven directly

    /// Draws in a scripted order, so a test can say which draw completes a chain.
    private final class Script: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int]
        init(_ values: [Int]) { self.values = values }
        func next() -> Int { lock.lock(); defer { lock.unlock() }; return values.removeFirst() }
    }

    private func chainResult(drawing values: [Int]) async -> CheckResult {
        let script = Script(values)
        let check = DrawPoolDriver.ChainCheck<Rounding>(
            sample: { _ in Rounding(raw: script.next()) },
            link: { $0 == $1 },
            property: { first, second, third in
                guard first == second, second == third else { return true }
                return first == third
            },
            formatCounterexample: { first, second, third, _ in "\(first), \(second), \(third)" },
            shrink: nil)
        return await DrawPoolDriver.runChains(
            DrawPoolDriver.Identity(protocolLaw: "Equatable.transitivity", tier: .strict),
            options: LawCheckOptions(budget: .custom(trials: values.count)),
            lookback: .max,
            check: check)
    }

    /// A pooled failure is a pair like any other, so it shrinks with the law's own
    /// property as the oracle. `$(250)` and `$(299)` share a dollar; stepping each
    /// toward zero while they still do ends at the smallest such pair.
    @Test func aPooledFailureShrinks() async throws {
        let script = Script([250, 299])
        let check = DrawPoolDriver.PairCheck<DollarMoney>(
            sample: { _ in DollarMoney(cents: script.next()) },
            property: { first, second in first != second || first.hashValue == second.hashValue },
            formatCounterexample: { first, second, _ in "\(first), \(second)" },
            shrink: { [DollarMoney(cents: $0.cents - $0.cents.signum())] })
        let result = await DrawPoolDriver.runPairs(
            DrawPoolDriver.Identity(protocolLaw: "Hashable.equalityConsistency", tier: .strict),
            options: LawCheckOptions(budget: .custom(trials: 2)),
            lookback: .max,
            check: check)
        #expect(result.counterexample == "$(200), $(201)")
        #expect(result.shrunkFrom == "$(250), $(299)")
        #expect(result.shrinkSteps == 50 + 98)
    }

    /// Both ways a new draw completes a chain: as an end, through a middle drawn
    /// earlier, and as the middle of two earlier draws. Dropping either branch
    /// misses one of these orders, and nothing else would notice.
    @Test func aChainIsFoundWhicheverMemberIsDrawnLast() async {
        // 2 is drawn last, and its only link is to the earlier middle 1.
        let endLast = await chainResult(drawing: [1, 0, 50, 2])
        #expect(endLast.counterexample == "R(0), R(1), R(2)" || endLast.counterexample == "R(2), R(1), R(0)")
        #expect(endLast.pairedDraws == PairedDraws(draws: 4, pairs: 6))

        // 1 is drawn last, and links two earlier draws that do not link each other.
        let middleLast = await chainResult(drawing: [0, 50, 2, 1])
        #expect(middleLast.isViolation, "the chain through the newest draw was not examined")
    }

    /// A pool with no chain passes, having compared every pair.
    @Test func aPoolWithoutAChainPasses() async {
        let result = await chainResult(drawing: [0, 10, 20, 30])
        #expect(!result.isViolation)
        #expect(result.pairedDraws == PairedDraws(draws: 4, pairs: 6))
    }
}
