import Foundation
import PropertyBased
@testable import PropertyLawAsync
import PropertyLawKit
import Testing

/// Appends from any thread; read once the run is over.
private final class Entries: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []

    func add(_ value: String) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

/// An operator whose `next()` spins on `Task.yield()` forever: at once, or,
/// with `afterCancel`, once the consumer is cancelled.
private struct Spinning: AsyncSequence, Sendable {
    typealias Element = Int

    let clock: LawClock
    let afterCancel: Bool

    func makeAsyncIterator() -> Iterator {
        Iterator(clock: clock, afterCancel: afterCancel)
    }

    struct Iterator: AsyncIteratorProtocol {
        let clock: LawClock
        let afterCancel: Bool

        mutating func next() async throws -> Int? {
            if afterCancel {
                while !Task.isCancelled {
                    try? await clock.sleep(until: clock.now.advanced(by: .milliseconds(50)), tolerance: nil)
                }
            }
            while true {
                await Task.yield()
            }
        }
    }
}

/// The step limit's precedence and mapping, teardown's and the last drain's
/// allowances, the trace's boundary and ordinals, and that the laws pass the
/// trial's schedule on. Most of these came out of hand mutation testing: each
/// kills a mutant the other tests let through. Counts are the scheduler's own
/// constants or measured in the test, never a job count the compiler decides.
struct ScheduleLimitTests {
    private static let seed = Seed(stateA: 11, stateB: 1, stateC: 2, stateD: 3)

    /// Escaped work that keeps in-run code spinning is reported as the escape,
    /// the cause, not as the step limit it runs into.
    @Test func anEscapeBehindALivelockIsReportedAsTheEscape() async throws {
        let handedBack = Latch()
        let ended = try await verdict(stepLimit: 1_000) { _ -> Int in
            Task {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    outsideQueue.async {
                        continuation.resume()
                        handedBack.set()
                    }
                }
            }
            await Task.yield()
            let giveUp = ContinuousClock.now.advanced(by: patience)
            while !handedBack.isSet, ContinuousClock.now < giveUp {
                restThisThread()
            }
            while true {
                await Task.yield()
            }
        }
        guard case .failure(.escaped(_, evidence: .taskResumedFromOutside)) = ended else {
            Issue.record("expected the escape, got \(ended)")
            return
        }
    }

    /// A run that fails on the limit decides its verdict after exactly the
    /// limit's steps.
    @Test func aRunThatFailsOnTheLimitHasItsVerdictAtTheLimit() async throws {
        let trace = ScheduleTrace()
        _ = try? await runInVirtualTime(stepLimit: 1_000, trace: trace) { _ -> Int in
            while true {
                await Task.yield()
            }
        }
        #expect(trace.verdictStep == 1_000)
    }

    /// Teardown runs exactly its allowance on a livelock that outlives the
    /// verdict, and the trace marks where the verdict was.
    @Test func teardownRunsExactlyItsAllowanceOnALivelock() async throws {
        let trace = ScheduleTrace()
        let stop = Latch()
        _ = try await runInVirtualTime(trace: trace) { clock in
            Task {
                try? await clock.sleep(for: .seconds(100))
                while !stop.isSet {
                    await Task.yield()
                }
            }
            return 1
        }
        stop.set()
        let boundary = try #require(trace.verdictStep)
        #expect(trace.steps.count - boundary == VirtualTimeScheduler.teardownStepLimit)
        #expect(trace.stepsBeforeVerdict.count == boundary)
    }

    /// After teardown's allowance runs out, the last drain still runs jobs on
    /// an allowance of its own; it is not recorded, so the trace stops
    /// growing while the spinner still runs.
    @Test func theLastDrainRunsAfterTeardownRunsOut() async throws {
        let trace = ScheduleTrace()
        let stop = Latch()
        let seen = Entries()
        _ = try await runInVirtualTime(trace: trace) { clock in
            Task {
                try? await clock.sleep(for: .seconds(100))
                while !stop.isSet {
                    seen.add("\(trace.steps.count)")
                    await Task.yield()
                }
            }
            return 1
        }
        stop.set()
        let frozen = "\(trace.steps.count)"
        #expect(seen.all.filter { $0 == frozen }.count > 1, "no spinner iteration ran in the last drain")
    }

    /// Ordinals name tasks in first-seen order: the root is 0 and three
    /// children are 1, 2 and 3.
    @Test func theTraceNamesTasksInFirstSeenOrder() async throws {
        let trace = ScheduleTrace()
        try await runInVirtualTime(trace: trace) { _ in
            await withTaskGroup(of: Void.self) { group in
                for _ in 0 ..< 3 {
                    group.addTask {
                        await Task.yield()
                    }
                }
            }
        }
        #expect(trace.steps.first?.task == 0)
        #expect(Set(trace.steps.compactMap(\.task)) == [0, 1, 2, 3])
    }

    /// A livelocking operator is a hang with the scheduler's own reason, and a
    /// consumer cancelled first keeps the "ignores cancellation" reading.
    @Test func aLivelockingOperatorIsAHang() async throws {
        do {
            _ = try await releasesUpstreamWhenConsumerLeaves(of: [1]) { _, clock in
                Spinning(clock: clock, afterCancel: false)
            }
            Issue.record("expected a hang")
        } catch let violation as LifetimeLawViolation {
            #expect(violation.description == "hang: \(VirtualTimeError.stepLimitExceeded(steps: 1_000_000))")
        }
        do {
            _ = try await releasesUpstreamWhenConsumerLeaves(of: [1]) { _, clock in
                Spinning(clock: clock, afterCancel: true)
            }
            Issue.record("expected a hang")
        } catch let violation as LifetimeLawViolation {
            #expect(violation.description.hasPrefix("hang: the consumer was cancelled"), "\(violation.description)")
        }
    }

    /// Every run of a seeded timed suite gets its trial's schedule seed, and a
    /// FIFO suite's runs get FIFO. Debounce gives the same output in every
    /// order, so only the runs themselves can show this.
    @Test func theTimedLawsPassTheScheduleOn() async throws {
        for (scheduling, isSeeded) in [(SchedulingStrategy.seeded, true), (.fifo, false)] {
            let log = RunOrderLog()
            try await RunOrderLog.$current.withValue(log) {
                _ = try await checkTimedAsyncSequencePropertyLaws(
                    for: [Int].self,
                    using: LifetimeLawResults.samples,
                    options: LawCheckOptions(budget: .sanity, seed: Self.seed, scheduling: scheduling)
                )
            }
            #expect(log.orders.count >= 400)
            #expect(log.orders.allSatisfy { ($0 != .fifo) == isSeeded }, "\(scheduling)")
        }
    }

    /// The cancellation law's own run takes the order it is given.
    @Test func theCancellationLawRunsInTheOrderItIsGiven() async throws {
        func events(_ order: JobOrder) async throws -> [String] {
            let log = Entries()
            _ = try await cancellationCeasesEmission(of: [1, 2], order: order) { clock in
                for index in 0 ..< 3 {
                    Task {
                        log.add("a\(index)")
                        await Task.yield()
                        log.add("b\(index)")
                    }
                }
                return clock
            }
            return log.all
        }
        let fifo = try await events(.fifo)
        var differs = false
        for schedule: UInt64 in 1 ... 20 where try await events(.seeded(schedule)) != fifo {
            differs = true
        }
        #expect(differs)
    }

    /// A seeded failure shrinks under the seed that found it, so the shrunk
    /// counterexample carries the same schedule seed.
    @Test func aSeededShrinkKeepsTheScheduleSeed() async throws {
        var results: [CheckResult] = []
        do {
            results = try await checkAsyncLifetimePropertyLaws(
                for: [Int].self,
                using: LifetimeLawResults.samples,
                options: LawCheckOptions(
                    budget: .sanity,
                    seed: Seed(stateA: 0x1234_5678_9ABC_DEF0, stateB: 0x0FED_CBA9_8765_4321, stateC: 42, stateD: 7),
                    scheduling: .seeded
                )
            ) { source, _ in ForwardingSequence(base: source, defect: .keepsUpstreamAfterDrop, delay: nil) }
        } catch let violation as PropertyLawViolation {
            results = violation.results
        }
        let name = LawIdentifier.asyncLifetime(.releasesUpstreamWhenConsumerLeaves).qualifiedName
        let result = try #require(results.first { $0.protocolLaw == name })
        #expect(result.shrinkSteps > 0)
        let schedule = try #require(result.shrunkFrom?.components(separatedBy: "; schedule seed ").last)
        #expect(result.counterexample?.hasSuffix("; schedule seed " + schedule) == true, "\(result)")
    }

    /// The timed suite's fingerprint replays under its own strategy, and a
    /// FIFO fingerprint is refused under `.seeded`.
    @Test func theTimedSuitesFingerprintPinsTheStrategy() async throws {
        let seeded = LawCheckOptions(budget: .sanity, seed: Self.seed, scheduling: .seeded)
        let results = try await checkTimedAsyncSequencePropertyLaws(
            for: [Int].self, using: LifetimeLawResults.samples, options: seeded
        )
        var replay = seeded
        replay.expectedReplayEnvironment = results[0].environment
        _ = try await checkTimedAsyncSequencePropertyLaws(
            for: [Int].self, using: LifetimeLawResults.samples, options: replay
        )
        var fifoStored = LawCheckOptions(budget: .sanity, seed: Self.seed, scheduling: .fifo)
        let fifoResults = try await checkTimedAsyncSequencePropertyLaws(
            for: [Int].self, using: LifetimeLawResults.samples, options: fifoStored
        )
        fifoStored.scheduling = .seeded
        fifoStored.expectedReplayEnvironment = fifoResults[0].environment
        await #expect(throws: ReplayEnvironmentMismatch.self) {
            _ = try await checkTimedAsyncSequencePropertyLaws(
                for: [Int].self, using: LifetimeLawResults.samples, options: fifoStored
            )
        }
    }
}
