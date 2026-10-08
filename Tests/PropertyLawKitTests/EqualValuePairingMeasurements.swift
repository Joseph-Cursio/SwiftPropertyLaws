import Foundation
import PropertyBased
import Testing
@testable import PropertyLawKit

/// **The measurements behind `EqualValuePairing`, reproducible on demand.**
///
/// Off by default — the detection table alone runs a few thousand suites. Run
/// with:
///
/// ```sh
/// PROPERTYLAW_MEASURE=1 swift test --filter EqualValuePairingDetection
/// PROPERTYLAW_MEASURE=1 swift test --filter EqualValuePairingMeasurements
/// ```
///
/// One at a time: the second suite reads process CPU time, which the first would
/// pollute. `PROPERTYLAW_MEASURE_SEEDS` sets the seed count for detection
/// (default 200, matching the simulation it checks). `PROPERTYLAW_MEASURE_TIERS`
/// (`.sanity,.standard,.thorough`) and `PROPERTYLAW_MEASURE_SUBJECTS`
/// (`int,array,prefix,bag`) narrow the cost tables.
///
/// **Cost is process CPU time, not wall-clock.** These were first taken on a
/// machine at a load average of 400 on 8 cores, where wall-clock measured the
/// scheduler; CPU time is what an uncontended CI runner would spend. It is in
/// whatever configuration `swift test` built — debug unless told otherwise,
/// which is the configuration CI pays for.
@Suite(
    "Equal-value pairing measurements",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["PROPERTYLAW_MEASURE"] != nil)
)
struct EqualValuePairingMeasurements {

    typealias DollarMoney = RareAntecedentTests.DollarMoney
    typealias AbsoluteOrder = RareAntecedentTests.AbsoluteOrder
    typealias Rounding = RareAntecedentTests.Rounding

    static let pairings: [(name: String, pairing: EqualValuePairing)] = [
        ("independent", .independent),
        ("every pair", .everyPairOfDraws),
        ("last 32", .recentDraws(window: 32))
    ]

    static var seeds: Int {
        Int(ProcessInfo.processInfo.environment["PROPERTYLAW_MEASURE_SEEDS"] ?? "") ?? 200
    }

    // MARK: - Cost

    /// A multiset: `==` sorts both sides, the way a bag or an unordered
    /// collection's equality has to. Correct, so every run spends its whole budget.
    struct Bag: Hashable, Sendable {
        let items: [Int]
        static func == (lhs: Bag, rhs: Bag) -> Bool { lhs.items.sorted() == rhs.items.sorted() }
        func hash(into hasher: inout Hasher) { hasher.combine(items.sorted()) }
    }

    private struct Subject: Sendable {
        let key: String
        let name: String
        let run: @Sendable (LawCheckOptions) async throws -> Void
    }

    private static let subjects: [Subject] = [
        Subject(key: "int", name: "`Int`") { options in
            _ = try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000), options: options)
        },
        Subject(key: "array", name: "`[Int]`, 100 random elements") { options in
            _ = try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).array(of: 100), options: options)
        },
        Subject(key: "prefix", name: "`[Int]`, 100 elements differing in the last") { options in
            _ = try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).map { Array(repeating: 7, count: 99) + [$0] },
                options: options)
        },
        Subject(key: "bag", name: "`Bag`, 100 elements, sorting `==`") { options in
            _ = try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).array(of: 100).map(Bag.init(items:)),
                options: options)
        }
    ]

    private static func wanted(_ variable: String) -> [String]? {
        ProcessInfo.processInfo.environment[variable]?.split(separator: ",").map(String.init)
    }

    private static var tiers: [(name: String, budget: TrialBudget)] {
        let all: [(String, TrialBudget)] = [(".sanity", .sanity), (".standard", .standard), (".thorough", .thorough)]
        return all.filter { wanted("PROPERTYLAW_MEASURE_TIERS")?.contains($0.0) ?? true }
    }

    /// Seconds of CPU this process has used, user and system.
    private static func processCPUSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }

    private static func cpuTime(_ body: () async throws -> Void) async rethrows -> String {
        let start = processCPUSeconds()
        try await body()
        return describe(seconds: processCPUSeconds() - start)
    }

    /// The whole `checkHashablePropertyLaws` suite, which is what a caller pays
    /// for: two of its seven laws pool, the other five do not.
    @Test func cost() async throws {
        let columns = Self.pairings.map(\.name).joined(separator: " | ")
        print("\n| `checkHashablePropertyLaws`, debug CPU | tier | " + columns + " |")
        print("|---|---|" + String(repeating: "---|", count: Self.pairings.count))
        let subjects = Self.subjects.filter { Self.wanted("PROPERTYLAW_MEASURE_SUBJECTS")?.contains($0.key) ?? true }
        for subject in subjects {
            for (tierName, budget) in Self.tiers {
                var cells: [String] = []
                for (_, pairing) in Self.pairings {
                    let options = LawCheckOptions(
                        budget: budget, seed: RareAntecedentTests.mixedSeed(0), equalValuePairing: pairing)
                    cells.append(try await Self.cpuTime { try await subject.run(options) })
                }
                print("| \(subject.name) | \(tierName) | " + cells.joined(separator: " | ") + " |")
            }
        }
    }

    // MARK: - Antisymmetry by sorting (measured, not shipped)

    /// The one law of the three with a cheaper route to its pairs. Sort the pool
    /// by `<` and the values the order calls equivalent sit in contiguous runs,
    /// so every pair that could satisfy antisymmetry's antecedent is found in
    /// `n log n` comparisons rather than `n²/2`. The runs are contiguous only if
    /// `<` is a strict weak ordering — which the `abs` bug is: it is a perfectly
    /// good order whose equivalence is coarser than `==`.
    private static func sortedPoolRefutesAntisymmetry<Value: Comparable>(_ pool: [Value]) -> Bool {
        let sorted = pool.sorted()
        var start = 0
        while start < sorted.count {
            var end = start + 1
            while end < sorted.count, !(sorted[start] < sorted[end]) { end += 1 }
            for first in start ..< end {
                for second in first + 1 ..< end {
                    let (lhs, rhs) = (sorted[first], sorted[second])
                    if lhs <= rhs, rhs <= lhs, lhs != rhs { return true }
                }
            }
            start = end
        }
        return false
    }

    private static func pool<Value, Shrinker: SendableSequenceType>(
        _ generator: Generator<Value, Shrinker>, seed: Seed, count: Int
    ) -> [Value] {
        var rng = seed.makeXoshiro()
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    @Test func antisymmetryBySorting() async {
        // Detection: the sorted pool is the pool `.everyPairOfDraws` draws from
        // the same seed, so the two must agree seed for seed.
        print("\n| `abs` ordering, .standard | every pair | sorted | disagreements |")
        print("|---|---|---|---|")
        for bound in [10_000, 1_000_000] {
            let generator = Gen<Int>.int(in: -bound ... bound).map(AbsoluteOrder.init(cents:))
            var pairwise = 0
            var sorted = 0
            var disagreements = 0
            for index in 0 ..< UInt64(Self.seeds) {
                let seed = RareAntecedentTests.mixedSeed(index)
                var pairwiseCaught = false
                do {
                    _ = try await checkComparablePropertyLaws(
                        using: generator,
                        options: LawCheckOptions(budget: .standard, seed: seed, equalValuePairing: .everyPairOfDraws),
                        laws: .ownOnly)
                } catch is PropertyLawViolation {
                    pairwiseCaught = true
                } catch {}
                let sortedCaught = Self.sortedPoolRefutesAntisymmetry(Self.pool(generator, seed: seed, count: 1_000))
                pairwise += pairwiseCaught ? 1 : 0
                sorted += sortedCaught ? 1 : 0
                disagreements += pairwiseCaught == sortedCaught ? 0 : 1
            }
            print("| ±\(bound) | \(pairwise * 100 / Self.seeds)% | \(sorted * 100 / Self.seeds)% | \(disagreements) |")
        }

        // Cost, over a correct `Int` so neither stops early.
        print("\n| antisymmetry alone, correct `Int`, debug CPU | tier | every pair | sorted |")
        print("|---|---|---|---|")
        let generator = Gen<Int>.int(in: -1_000_000 ... 1_000_000)
        for (tierName, budget) in Self.tiers {
            let options = LawCheckOptions(
                budget: budget, seed: RareAntecedentTests.mixedSeed(0), equalValuePairing: .everyPairOfDraws)
            let pairwise = await Self.cpuTime {
                _ = await runEqualValueBinaryLaw(
                    "Comparable.antisymmetry",
                    source: .sampling(generator),
                    options: options,
                    property: { first, second in
                        guard first <= second, second <= first else { return true }
                        return first == second
                    },
                    formatCounterexample: { _, _, _ in "" })
            }
            let sorted = await Self.cpuTime {
                _ = Self.sortedPoolRefutesAntisymmetry(
                    Self.pool(generator, seed: RareAntecedentTests.mixedSeed(0), count: budget.trialCount))
            }
            print("| `Int` | \(tierName) | \(pairwise) | \(sorted) |")
        }
    }

    private static func describe(seconds: Double) -> String {
        if seconds < 1 { return "\(Int((seconds * 1_000).rounded())) ms" }
        return String(format: "%.1f s", seconds)
    }
}

/// Detection over well-mixed seeds at `.standard`, one parameterized case per
/// bug and pairing so the cases run in parallel. Each prints one row of
/// `| bug | pairing | caught |`.
@Suite(
    "Equal-value pairing detection",
    .enabled(if: ProcessInfo.processInfo.environment["PROPERTYLAW_MEASURE"] != nil)
)
struct EqualValuePairingDetection {

    typealias DollarMoney = RareAntecedentTests.DollarMoney
    typealias AbsoluteOrder = RareAntecedentTests.AbsoluteOrder
    typealias Rounding = RareAntecedentTests.Rounding

    struct Bug: Sendable {
        let name: String
        let law: String
        let run: @Sendable (LawCheckOptions) async throws -> Void
    }

    static let bugs: [Bug] = [
        Bug(name: "dollar `==`, ±1 000 000", law: "Hashable.equalityConsistency") { options in
            _ = try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).map(DollarMoney.init(cents:)),
                options: options, laws: .ownOnly)
        },
        Bug(name: "dollar `==`, ±10 000", law: "Hashable.equalityConsistency") { options in
            _ = try await checkHashablePropertyLaws(
                using: Gen<Int>.int(in: -10_000 ... 10_000).map(DollarMoney.init(cents:)),
                options: options, laws: .ownOnly)
        },
        Bug(name: "`abs` ordering, ±10 000", law: "Comparable.antisymmetry") { options in
            _ = try await checkComparablePropertyLaws(
                using: Gen<Int>.int(in: -10_000 ... 10_000).map(AbsoluteOrder.init(cents:)),
                options: options, laws: .ownOnly)
        },
        Bug(name: "`abs` ordering, ±1 000 000", law: "Comparable.antisymmetry") { options in
            _ = try await checkComparablePropertyLaws(
                using: Gen<Int>.int(in: -1_000_000 ... 1_000_000).map(AbsoluteOrder.init(cents:)),
                options: options, laws: .ownOnly)
        },
        Bug(name: "\"within 1\" `==`, 0 … 200", law: "Equatable.transitivity") { options in
            _ = try await checkEquatablePropertyLaws(
                using: Gen<Int>.int(in: 0 ... 200).map(Rounding.init(raw:)), options: options)
        },
        Bug(name: "\"within 1\" `==`, ±10 000", law: "Equatable.transitivity") { options in
            _ = try await checkEquatablePropertyLaws(
                using: Gen<Int>.int(in: -10_000 ... 10_000).map(Rounding.init(raw:)), options: options)
        }
    ]

    @Test(arguments: 0 ..< bugs.count, 0 ..< EqualValuePairingMeasurements.pairings.count)
    func detection(bug index: Int, pairing column: Int) async {
        let bug = Self.bugs[index]
        let (name, pairing) = EqualValuePairingMeasurements.pairings[column]
        let seeds = EqualValuePairingMeasurements.seeds
        var caught = 0
        for seed in 0 ..< UInt64(seeds) {
            let options = LawCheckOptions(
                budget: .standard, seed: RareAntecedentTests.mixedSeed(seed), equalValuePairing: pairing)
            do {
                try await bug.run(options)
            } catch let violation as PropertyLawViolation {
                if violation.results.contains(where: { $0.isViolation && $0.protocolLaw == bug.law }) {
                    caught += 1
                }
            } catch {}
        }
        print("| \(bug.name) | \(name) | \(caught * 100 / seeds)% |")
    }
}
