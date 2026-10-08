import AsyncAlgorithms
import Foundation
import Testing
@testable import PropertyLawAsync

struct VirtualTimeTests {

    /// The flake this scheduler replaced `TestClock` to fix, reproduced
    /// without needing a loaded machine. Each `next()` spends 2 ms on the CPU
    /// before it reaches its sleep — what a descheduled thread looks like.
    /// `TestClock.advance` finishes in about a millisecond of wall time
    /// whatever it is asked to cover, so its sleeper registered after the
    /// advance had returned and was never woken: measured, the consumer
    /// never completed at 1, 2, 5 or 10 ms. Here an empty queue is the only
    /// signal time may move, so the slow source is simply waited for.
    @Test func aSourceSlowToReachItsSleepIsWaitedFor() async throws {
        let output = try await runInVirtualTime { clock in
            let source = SlowToSleepSource(clock: clock, elements: [1, 2, 3], busy: .milliseconds(2))
            return try await collect(source.debounce(for: .milliseconds(10), clock: clock))
        }
        #expect(output == [3])
    }

    @Test func sleepersWakeInDeadlineOrderThenRegistrationOrder() async throws {
        let wakes = try await runInVirtualTime { clock in
            let log = WakeLog()
            let sleepers = [("late", 5), ("first", 3), ("second", 3)].map { label, milliseconds in
                Task {
                    try await clock.sleep(until: .init(offset: .milliseconds(milliseconds)))
                    log.record(label, at: clock.now.offset)
                }
            }
            for sleeper in sleepers { try await sleeper.value }
            return log.entries
        }
        #expect(wakes.map(\.label) == ["first", "second", "late"])
        // Time moves to a deadline and nowhere else.
        #expect(wakes.map(\.time) == [.milliseconds(3), .milliseconds(3), .milliseconds(5)])
    }

    @Test func aDeadlineNotInTheFutureDoesNotMoveTime() async throws {
        let now = try await runInVirtualTime { clock in
            try await clock.sleep(for: .zero)
            try await clock.sleep(until: .init(offset: .zero))
            return clock.now.offset
        }
        #expect(now == .zero)
    }

    @Test func aStuckRunIsReportedNotAwaited() async throws {
        let parked = ParkedTask()
        await #expect(throws: VirtualTimeError.deadlock(stuckAt: .milliseconds(4))) {
            try await runInVirtualTime { clock in
                try await clock.sleep(for: .milliseconds(4))
                await parked.park()
            }
        }
        // Released from outside the run, so the parked body finishes on the
        // ordinary executor rather than leaking.
        parked.release()
    }

    @Test func aRunThatWouldPassItsHorizonFailsInsteadOfAdvancing() async throws {
        await #expect(
            throws: VirtualTimeError.horizonExceeded(
                horizon: .milliseconds(20),
                nextDeadline: .milliseconds(50)
            )
        ) {
            try await runInVirtualTime(horizon: .milliseconds(20)) { clock in
                try await clock.sleep(for: .milliseconds(50))
            }
        }
    }

    @Test func cancellationWakesASleeperWithoutMovingTime() async throws {
        let (outcome, now) = try await runInVirtualTime { clock in
            let sleeper = Task { try await clock.sleep(for: .milliseconds(100)) }
            try await clock.sleep(for: .milliseconds(10))
            sleeper.cancel()
            let outcome = await sleeper.result
            return (outcome, clock.now.offset)
        }
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(now == .milliseconds(10))
    }

    /// A body may return while a task it started is still asleep. Nothing
    /// will advance the clock again, so the run wakes it on the way out
    /// rather than leaving it parked on a continuation forever. Checked
    /// without awaiting the task, so a regression fails instead of hanging.
    @Test func aSleeperTheBodyLeftBehindIsWokenWhenTheRunEnds() async throws {
        let left = LeftBehind()
        let now = try await runInVirtualTime { clock in
            Task {
                do {
                    try await clock.sleep(for: .seconds(1))
                    left.record(.success(()))
                } catch {
                    left.record(.failure(error))
                }
            }
            return clock.now.offset
        }
        #expect(now == .zero)
        let outcome = try #require(left.outcome, "the sleeper was still parked after the run returned")
        #expect(throws: CancellationError.self) { try outcome.get() }
    }

    /// A cancel can reach the timeline before the sleep it targets has
    /// registered — the handler runs at once for a task cancelled on entry,
    /// and from another thread it can simply arrive first. The ticket it
    /// leaves must still fail the sleep, or the task sleeps out its deadline.
    @Test func aCancelThatArrivesBeforeItsSleepIsHonoured() async {
        let timeline = VirtualTimeline()
        let ticket = timeline.issueTicket()
        timeline.cancel(ticket)
        await #expect(throws: CancellationError.self) {
            try await withCheckedThrowingContinuation { continuation in
                timeline.suspend(ticket, until: .init(offset: .seconds(1)), continuation)
            }
        }
        #expect(timeline.pendingSleeperCount == 0)
    }

    @Test func concurrentRunsKeepSeparateQueuesAndClocks() async throws {
        let outputs = try await withThrowingTaskGroup(of: [Int].self) { group in
            for _ in 0 ..< 16 {
                group.addTask {
                    try await runInVirtualTime { clock in
                        let source = TimedSource(
                            clock: clock,
                            gaps: [.milliseconds(1), .milliseconds(1), .milliseconds(1)],
                            elements: [1, 2, 3]
                        )
                        return try await collect(source.debounce(for: .milliseconds(10), clock: clock))
                    }
                }
            }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        #expect(outputs == Array(repeating: [3], count: 16))
    }

    /// `withMainSerialExecutor` sends every global job in the process to one
    /// thread; this hook diverts only the run's own. While a run's thread is
    /// busy, a task started elsewhere must still get to run — the test spins
    /// inside the run until it does.
    @Test func otherThreadsKeepTheirConcurrencyDuringARun() async throws {
        let started = Flag()
        let observed = Flag()
        async let sawOutsideTask = runInVirtualTime { _ in
            started.set()
            let giveUp = ContinuousClock.now.advanced(by: .seconds(10))
            while observed.isSet == false, ContinuousClock.now < giveUp {}
            return observed.isSet
        }
        while started.isSet == false { try await Task.sleep(for: .milliseconds(1)) }
        Task.detached { observed.set() }
        #expect(try await sawOutsideTask)
    }
}

/// The hook's bookkeeping, against a slot of the test's own so the process's
/// real hook is never touched while other runs may be using it.
struct GlobalEnqueueHookTests {
    private static let foreign: GlobalEnqueueHook.Hook = { job, original in original(job) }

    @Test func installsOnceAndRemovesWithTheLastRun() throws {
        try withFakeSlot { slot, hook in
            try hook.acquire()
            try hook.acquire()
            #expect(slot.pointee != nil)
            hook.release()
            #expect(slot.pointee != nil, "removed while a run was still active")
            #expect(hook.isIntact)
            hook.release()
            #expect(slot.pointee == nil)
            #expect(hook.isInstalled == false)
        }
    }

    @Test func refusesAHookItDidNotInstall() throws {
        try withFakeSlot { slot, hook in
            slot.pointee = Self.foreign
            #expect(throws: VirtualTimeError.foreignHookInstalled) { try hook.acquire() }
            #expect(rawBits(slot) == rawBits(of: Self.foreign), "a foreign hook was replaced")
        }
    }

    @Test func noticesBeingReplacedAndLeavesTheReplacementInPlace() throws {
        try withFakeSlot { slot, hook in
            try hook.acquire()
            slot.pointee = Self.foreign
            #expect(hook.isIntact == false)
            #expect(throws: VirtualTimeError.foreignHookInstalled) { try hook.acquire() }
            hook.release()
            #expect(rawBits(slot) == rawBits(of: Self.foreign), "removed someone else's hook")
        }
    }

    @Test func aMissingSlotIsReportedNotAssumed() {
        #expect(throws: VirtualTimeError.hookUnavailable) {
            try GlobalEnqueueHook(slot: nil).acquire()
        }
    }

    private func withFakeSlot(
        _ body: (UnsafeMutablePointer<GlobalEnqueueHook.Hook?>, GlobalEnqueueHook) throws -> Void
    ) throws {
        let slot = UnsafeMutablePointer<GlobalEnqueueHook.Hook?>.allocate(capacity: 1)
        slot.initialize(to: nil)
        defer { slot.deallocate() }
        try body(slot, GlobalEnqueueHook(slot: slot))
    }

    private func rawBits(_ slot: UnsafeMutablePointer<GlobalEnqueueHook.Hook?>) -> UInt {
        UnsafeRawPointer(slot).load(as: UInt.self)
    }

    private func rawBits(of hook: GlobalEnqueueHook.Hook) -> UInt {
        var copy: GlobalEnqueueHook.Hook? = hook
        return withUnsafeBytes(of: &copy) { $0.load(as: UInt.self) }
    }
}

// MARK: - Fixtures

/// A timed source whose iterator burns `busy` of CPU before every sleep.
private struct SlowToSleepSource: AsyncSequence, Sendable {
    let clock: VirtualClock
    let elements: [Int]
    let busy: Duration

    struct AsyncIterator: AsyncIteratorProtocol {
        let source: SlowToSleepSource
        var position = 0

        mutating func next() async throws -> Int? {
            guard position < source.elements.count else { return nil }
            let end = ContinuousClock.now.advanced(by: source.busy)
            while ContinuousClock.now < end {}
            try await source.clock.sleep(for: .milliseconds(1))
            defer { position += 1 }
            return source.elements[position]
        }
    }

    func makeAsyncIterator() -> AsyncIterator { AsyncIterator(source: self) }
}

private final class WakeLog: @unchecked Sendable {
    struct Entry: Sendable {
        let label: String
        let time: Duration
    }

    private let lock = NSLock()
    private var stored: [Entry] = []

    var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ label: String, at time: Duration) {
        lock.lock()
        stored.append(Entry(label: label, time: time))
        lock.unlock()
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// How a task started inside a run ended, recorded by the task itself.
private final class LeftBehind: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Void, Error>?

    var outcome: Result<Void, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ outcome: Result<Void, Error>) {
        lock.lock()
        stored = outcome
        lock.unlock()
    }
}

/// A continuation nothing inside a run will resume.
private final class ParkedTask: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func park() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume()
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func release() {
        lock.lock()
        released = true
        let parked = continuation
        continuation = nil
        lock.unlock()
        parked?.resume()
    }
}
