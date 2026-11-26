import Foundation
@testable import PropertyLawAsync
import Testing

/// Appends from any thread; read once the run is over.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func add(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    var all: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

/// Three tasks that each log, yield and log again: under FIFO they take
/// turns, and other orders are reachable only by choosing among them.
private func interleaved(order: JobOrder, trace: ScheduleTrace? = nil) async throws -> [String] {
    let log = EventLog()
    try await runInVirtualTime(order: order, trace: trace) { _ in
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 3 {
                group.addTask {
                    log.add("a\(index)")
                    await Task.yield()
                    log.add("b\(index)")
                }
            }
        }
    }
    return log.all
}

/// A task that re-enqueues itself until told to stop, and ignores
/// cancellation, as a livelock does.
@discardableResult
private func spinUntil(_ stop: @escaping @Sendable () -> Bool) -> Task<Void, Never> {
    Task {
        while !stop() {
            await Task.yield()
        }
    }
}

/// The order a seed gives, the pick rule a stored seed depends on, and the step
/// limit. The pick rule is pinned on plain values, so nothing here depends on
/// how the compiler splits code into jobs; the runs check only body-level
/// events and properties that hold whatever the job count.
struct ScheduleOrderTests {
    /// Published SplitMix64 outputs for seed 1,234,567, the same vector the
    /// swift-async-algorithms fork pins for its seeded order.
    @Test func splitMix64MatchesTheReferenceVector() {
        var generator = SplitMix64(seed: 1_234_567)
        #expect((0 ..< 5).map { _ in generator.next() } == [
            6_457_827_717_110_365_317,
            3_203_168_211_198_807_973,
            9_817_491_932_198_370_423,
            4_593_380_528_125_082_431,
            16_408_922_859_458_223_821,
        ])
    }

    /// FIFO takes the oldest and never draws.
    @Test func fifoTakesTheOldest() {
        let queue = JobQueue<Int>(order: .fifo)
        for job in 1 ... 4 {
            queue.append(job)
        }
        var taken: [Int] = []
        while let pick = queue.next() {
            #expect(pick.picked == 0)
            taken.append(pick.job)
        }
        #expect(taken == [1, 2, 3, 4])
        #expect(queue.isEmpty)
    }

    /// A seeded pick takes the job at `next() % n` among the pending, in
    /// enqueue order, and leaves the rest in that order.
    @Test func aSeededPickTakesTheDrawnPositionAndKeepsTheRestInOrder() {
        var reference = SplitMix64(seed: 99)
        let queue = JobQueue<Int>(order: .seeded(99))
        var pending = [10, 20, 30, 40, 50]
        for job in pending {
            queue.append(job)
        }
        while pending.count > 1 {
            let expected = Int(reference.next() % UInt64(pending.count))
            let pick = try? #require(queue.next())
            #expect(pick?.pending == pending.count)
            #expect(pick?.picked == expected)
            #expect(pick?.job == pending.remove(at: expected))
        }
        #expect(queue.next()?.job == pending.first)
    }

    /// With one job pending nothing is drawn, so a job added where there was
    /// no choice shifts no later choice.
    @Test func aSingleCandidateDrawsNothing() {
        let withExtraJob = JobQueue<Int>(order: .seeded(7))
        withExtraJob.append(0)
        #expect(withExtraJob.next()?.picked == 0)
        let without = JobQueue<Int>(order: .seeded(7))
        for job in 1 ... 6 {
            withExtraJob.append(job)
            without.append(job)
        }
        var picksWith: [Int] = []
        var picksWithout: [Int] = []
        while let pick = withExtraJob.next() {
            picksWith.append(pick.job)
        }
        while let pick = without.next() {
            picksWithout.append(pick.job)
        }
        #expect(picksWith == picksWithout)
    }

    @Test func fifoNeverChoosesAnythingButTheOldest() async throws {
        let trace = ScheduleTrace()
        let events = try await interleaved(order: .fifo, trace: trace)
        #expect(events == ["a0", "a1", "a2", "b0", "b1", "b2"])
        #expect(!trace.choices.isEmpty)
        #expect(trace.choices.allSatisfy { $0.picked == 0 })
    }

    /// One seed is one interleaving: the same steps up to the verdict and the
    /// same events, run after run.
    @Test func aSeedGivesTheSameRunEveryTime() async throws {
        for seed: UInt64 in [1, 2, 3, 17, 99] {
            let first = ScheduleTrace()
            let firstEvents = try await interleaved(order: .seeded(seed), trace: first)
            for _ in 0 ..< 3 {
                let again = ScheduleTrace()
                #expect(try await interleaved(order: .seeded(seed), trace: again) == firstEvents)
                #expect(again.stepsBeforeVerdict == first.stepsBeforeVerdict, "seed \(seed)")
            }
        }
    }

    /// Seeds reach interleavings FIFO never takes, and every one still runs
    /// each task's two halves in order.
    @Test func seedsExploreOrdersFifoNeverTakes() async throws {
        let fifo = try await interleaved(order: .fifo)
        var seen: Set<[String]> = []
        for seed: UInt64 in 1 ... 50 {
            let events = try await interleaved(order: .seeded(seed))
            seen.insert(events)
            for index in 0 ..< 3 {
                let first = try #require(events.firstIndex(of: "a\(index)"))
                let second = try #require(events.firstIndex(of: "b\(index)"))
                #expect(first < second, "seed \(seed): \(events)")
            }
        }
        #expect(seen.count > 2, "\(seen)")
        #expect(seen.contains { $0 != fifo })
    }

    @Test func theDefaultLimitsArePinned() {
        #expect(VirtualTimeScheduler.defaultStepLimit == 1_000_000)
        #expect(VirtualTimeScheduler.teardownStepLimit == 10_000)
        #expect(VirtualTimeScheduler.finalDrainStepLimit == 1_000)
    }

    /// A body whose queue never empties fails on the limit, under either order.
    @Test(arguments: [JobOrder.fifo, .seeded(5)])
    func aLivelockFailsOnTheStepLimit(order: JobOrder) async throws {
        let ended = try await verdict(order: order, stepLimit: 1_000) { _ -> Int in
            while true {
                await Task.yield()
            }
        }
        #expect(ended == .failure(.stepLimitExceeded(steps: 1_000)))
    }

    /// A yield costs a few jobs (five in a debug build), so 900 yields fit in
    /// 10,000 steps with room to spare.
    @Test func aBodyWithinTheLimitSucceeds() async throws {
        let ended = try await verdict(stepLimit: 10_000) { _ in
            for _ in 0 ..< 900 {
                await Task.yield()
            }
            return 1
        }
        #expect(ended == .success(1))
    }

    /// The limit counts jobs that ran, so a run that empties its queue on
    /// exactly its last allowed step settles, and one step fewer does not. How
    /// many jobs a body takes depends on the compiler, so it is measured.
    @Test func aRunThatSettlesOnItsLastStepSucceeds() async throws {
        let trace = ScheduleTrace()
        _ = try await runInVirtualTime(trace: trace) { _ in 1 }
        let steps = try #require(trace.verdictStep)
        #expect(try await verdict(stepLimit: steps) { _ in 1 } == .success(1))
        #expect(try await verdict(stepLimit: steps - 1) { _ in 1 } == .failure(.stepLimitExceeded(steps: steps - 1)))
    }

    /// `settle()` waits for an empty queue; a livelock beside it is reported
    /// as the livelock, not as a deadlock or a passed horizon.
    @Test func aLivelockBesideASettleIsReportedAsTheLivelock() async throws {
        let ended = try await verdict(stepLimit: 1_000) { clock in
            spinUntil { false }
            await clock.settle()
            return 1
        }
        #expect(ended == .failure(.stepLimitExceeded(steps: 1_000)))
    }

    /// A task asleep when the body returns is woken by teardown's
    /// cancellation. One that then re-enqueues itself forever is abandoned
    /// when teardown's steps run out, and the run returns its result instead
    /// of spinning.
    @Test func teardownAbandonsALivelockThatStartsAfterTheVerdict() async throws {
        let stop = Latch()
        let woke = Latch()
        let ended = try await verdict { clock in
            Task {
                try? await clock.sleep(for: .seconds(100))
                woke.set()
                while !stop.isSet {
                    await Task.yield()
                }
            }
            return 1
        }
        stop.set()
        #expect(ended == .success(1))
        #expect(woke.isSet, "teardown never woke the sleeper")
    }

    /// Teardown still runs out work that fits its allowance: 1,500 yields
    /// after the sleeper wakes, a few thousand steps, finish within 10,000.
    @Test func teardownFinishesWorkWithinItsAllowance() async throws {
        let finished = Latch()
        let ended = try await verdict { clock in
            Task {
                try? await clock.sleep(for: .seconds(100))
                for _ in 0 ..< 1_500 {
                    await Task.yield()
                }
                finished.set()
            }
            return 1
        }
        #expect(ended == .success(1))
        #expect(finished.isSet)
    }
}
