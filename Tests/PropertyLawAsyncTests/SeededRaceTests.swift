import PropertyBased
@testable import PropertyLawAsync
import PropertyLawKit
import Testing

/// The seeded order on a planted race (``RacingShareSequence``), the shape of
/// swift-async-algorithms issue 473's case 12: FIFO never finds it, seeds do,
/// the fixed twin is clean under both, and a failing seed replays. Assertions
/// are about verdicts and replays, never about literal seed numbers or job
/// counts, which depend on how the compiler splits code into jobs.
struct SeededRaceTests {
    private static func options(_ run: UInt64, _ scheduling: SchedulingStrategy) -> LawCheckOptions {
        LawCheckOptions(
            budget: .sanity, seed: Seed(stateA: run, stateB: 1, stateC: 2, stateD: 3), scheduling: scheduling
        )
    }

    /// The results of the laws that failed, keyed by law.
    private static func failures(
        fixed: Bool,
        _ options: LawCheckOptions
    ) async throws -> [AsyncLifetimeLaw: CheckResult] {
        do {
            try await checkAsyncLifetimePropertyLaws(
                for: [Int].self, using: LifetimeLawResults.samples, options: options
            ) { source, _ in RacingShareSequence(base: source, fixed: fixed) }
            return [:]
        } catch let violation as PropertyLawViolation {
            var failed: [AsyncLifetimeLaw: CheckResult] = [:]
            for result in violation.results {
                let name = String(result.protocolLaw.dropFirst("AsyncLifetime.".count))
                failed[try #require(AsyncLifetimeLaw(rawValue: name))] = result
            }
            return failed
        }
    }

    /// The planted race's result for the case-12 law, if it failed.
    private static func caseTwelve(_ options: LawCheckOptions) async throws -> CheckResult? {
        try await failures(fixed: false, options)[.releasesUpstreamWhenSequenceDroppedLast]
    }

    @Test(arguments: [false, true])
    func fifoPassesEveryLaw(fixed: Bool) async throws {
        let failed = try await Self.failures(fixed: fixed, Self.options(1, .fifo))
        #expect(failed.isEmpty, "\(failed)")
    }

    /// Seeds find the leak, and only the case-12 law reports it: the planted
    /// race is in the order of the drops, which no other law exercises.
    @Test func seedsFindThePlantedLeakAndOnlyTheCase12Law() async throws {
        var found = 0
        for run: UInt64 in 1 ... 5 {
            let failed = try await Self.failures(fixed: false, Self.options(run, .seeded))
            #expect(Set(failed.keys).isSubset(of: [.releasesUpstreamWhenSequenceDroppedLast]), "run \(run): \(failed)")
            if let result = failed[.releasesUpstreamWhenSequenceDroppedLast] {
                found += 1
                #expect(result.counterexample?.contains("then dropped its iterator and then the sequence") == true)
                #expect(result.counterexample?.contains("; schedule seed ") == true)
                #expect(result.environment.scheduling == "seeded/1")
            }
        }
        #expect(found > 0, "no seeded run found the planted race")
    }

    @Test func theFixedTwinPassesUnderEverySeed() async throws {
        for run: UInt64 in 1 ... 10 {
            let failed = try await Self.failures(fixed: true, Self.options(run, .seeded))
            #expect(failed.isEmpty, "run \(run): \(failed)")
        }
    }

    /// The same run seed and strategy reproduce the failure: the same trial,
    /// counterexample and shrinking, with every earlier trial passing again.
    @Test func aFailingRunReplaysFromItsSeed() async throws {
        let first = try #require(try await Self.caseTwelve(Self.options(1, .seeded)))
        for _ in 0 ..< 3 {
            let again = try #require(try await Self.caseTwelve(Self.options(1, .seeded)))
            #expect(again.trials == first.trials)
            #expect(again.counterexample == first.counterexample)
            #expect(again.shrunkFrom == first.shrunkFrom)
            #expect(again.shrinkSteps == first.shrinkSteps)
        }
    }

    /// The schedule seed in the counterexample is enough to replay that one
    /// trial on its own, and FIFO on the same input passes.
    @Test func theCounterexamplesScheduleSeedReplaysOneTrial() async throws {
        let result = try #require(try await Self.caseTwelve(Self.options(1, .seeded)))
        let text = try #require(result.counterexample)
        let source = try #require(text.split(separator: ";").first?.dropFirst("source = ".count))
        let sample = source.dropFirst().dropLast().split(separator: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        let schedule = try #require(text.components(separatedBy: "; schedule seed ").last.flatMap { UInt64($0) })
        typealias Racing = RacingShareSequence<LifetimeProbeSource<Int>>
        let operation: @Sendable (LifetimeProbeSource<Int>, LawClock) -> Racing = { source, _ in
            RacingShareSequence(base: source, fixed: false)
        }
        let seeded = try await releasesUpstreamWhenSequenceDroppedLast(
            of: sample, applying: operation, order: .seeded(schedule)
        )
        #expect(seeded != nil, "the schedule seed did not reproduce the leak on \(sample)")
        #expect(try await releasesUpstreamWhenSequenceDroppedLast(of: sample, applying: operation) == nil)
    }

    /// A seeded result's own fingerprint replays under the seeded strategy and
    /// is refused under FIFO, which would silently test a different run.
    @Test func theFingerprintPinsTheStrategy() async throws {
        let result = try #require(try await Self.caseTwelve(Self.options(1, .seeded)))
        var replay = Self.options(1, .seeded)
        replay.expectedReplayEnvironment = result.environment
        let again = try await Self.failures(fixed: false, replay)[.releasesUpstreamWhenSequenceDroppedLast]
        #expect(again?.counterexample == result.counterexample)
        var underFifo = Self.options(1, .fifo)
        underFifo.expectedReplayEnvironment = result.environment
        await #expect(throws: ReplayEnvironmentMismatch.self) {
            _ = try await Self.failures(fixed: false, underFifo)
        }
    }

    /// The failure text names the strategy the seed replays under.
    @Test func theFailureTextNamesTheStrategy() async throws {
        do {
            try await checkAsyncLifetimePropertyLaws(
                for: [Int].self, using: LifetimeLawResults.samples, options: Self.options(1, .seeded)
            ) { source, _ in RacingShareSequence(base: source, fixed: false) }
            Issue.record("expected the planted race to be found")
        } catch let violation as PropertyLawViolation {
            #expect(violation.description.contains("(scheduling: seeded/1"), "\(violation)")
        }
    }
}
