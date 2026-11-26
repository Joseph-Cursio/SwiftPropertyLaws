import Foundation

/// The sleepers of one virtual-time run, and the time they agree on.
final class VirtualTimeline: @unchecked Sendable {
    private struct Sleeper {
        let ticket: Int
        let deadline: VirtualClock.Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = VirtualClock.Instant(offset: .zero)
    private var sleepers: [Sleeper] = []
    private var cancelledTickets: Set<Int> = []
    private var nextTicket = 0
    private var settleWaiters: [CheckedContinuation<Void, Never>] = []
    /// The run this timeline belongs to, if any. A sleep or settle from any
    /// other thread is work that escaped it.
    private let owner: VirtualTimeScheduler?

    init(owner: VirtualTimeScheduler? = nil) {
        self.owner = owner
    }

    var now: VirtualClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    var earliestDeadline: VirtualClock.Instant? {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.map(\.deadline).min()
    }

    var pendingSleeperCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepers.count
    }

    /// A ticket per `sleep` call, so cancellation can find its sleeper and
    /// ties between equal deadlines break in registration order.
    func issueTicket() -> Int {
        lock.lock()
        defer { lock.unlock() }
        nextTicket += 1
        return nextTicket
    }

    func suspend(
        _ ticket: Int,
        until deadline: VirtualClock.Instant,
        _ continuation: CheckedContinuation<Void, Error>
    ) {
        noteCallingThread()
        lock.lock()
        // The cancellation handler can run before the continuation exists —
        // it runs at once for a task cancelled on entry — so a cancel that
        // found no sleeper leaves its ticket here to be honoured now.
        if cancelledTickets.remove(ticket) != nil {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        guard deadline > current else {
            lock.unlock()
            continuation.resume()
            return
        }
        sleepers.append(Sleeper(ticket: ticket, deadline: deadline, continuation: continuation))
        lock.unlock()
    }

    func cancel(_ ticket: Int) {
        lock.lock()
        guard let index = sleepers.firstIndex(where: { $0.ticket == ticket }) else {
            cancelledTickets.insert(ticket)
            lock.unlock()
            return
        }
        let sleeper = sleepers.remove(at: index)
        lock.unlock()
        sleeper.continuation.resume(throwing: CancellationError())
    }

    /// Wake the earliest sleeper — the first registered, among equals — and
    /// move `now` to its deadline. Returns `false` when nobody is sleeping.
    @discardableResult
    func fireEarliest() -> Bool {
        lock.lock()
        guard let index = sleepers.indices.min(by: { lhs, rhs in
            (sleepers[lhs].deadline, sleepers[lhs].ticket)
                < (sleepers[rhs].deadline, sleepers[rhs].ticket)
        }) else {
            lock.unlock()
            return false
        }
        let sleeper = sleepers.remove(at: index)
        current = sleeper.deadline
        lock.unlock()
        sleeper.continuation.resume()
        return true
    }

    /// Park a ``VirtualClock/settle()`` caller until the scheduler next finds
    /// its queue empty.
    func awaitSettle(_ continuation: CheckedContinuation<Void, Never>) {
        noteCallingThread()
        lock.lock()
        settleWaiters.append(continuation)
        lock.unlock()
    }

    /// Resume every ``VirtualClock/settle()`` caller. The scheduler calls this
    /// only with its queue empty, before it moves time. Returns `false` when
    /// nobody was waiting.
    @discardableResult
    func resumeSettled() -> Bool {
        lock.lock()
        let woken = settleWaiters
        settleWaiters.removeAll()
        lock.unlock()
        for waiter in woken {
            waiter.resume()
        }
        return !woken.isEmpty
    }

    /// Tell the owning run when its clock is used from a thread outside it.
    private func noteCallingThread() {
        if let owner, VirtualTimeScheduler.current !== owner {
            owner.noteEscape(.clockUsedFromOutside)
        }
    }

    /// Wake every sleeper with `CancellationError`, for tearing down a run
    /// that could not finish.
    func cancelAll() {
        lock.lock()
        let woken = sleepers
        sleepers.removeAll()
        lock.unlock()
        for sleeper in woken {
            sleeper.continuation.resume(throwing: CancellationError())
        }
    }
}

/// A `Clock` whose time moves only when ``runInVirtualTime(horizon:_:)``
/// finds every task in the run blocked.
///
/// The clock itself never advances. It records who is sleeping until when;
/// the scheduler, having drained every runnable job, wakes the earliest
/// sleeper and moves `now` to its deadline. Because that happens only at
/// quiescence, a task that is slow to reach its next sleep is waited for
/// rather than overtaken — which is the property a yield-counting clock
/// cannot offer, and the reason this one exists. See `VirtualTimeScheduler`.
///
/// Sleepers sharing a deadline wake in registration order, one at a time,
/// each running to quiescence before the next. Real timers that fire
/// together have no defined order; this one is arbitrary but fixed, which
/// is what a determinism law needs.
struct VirtualClock: Clock {
    struct Instant: InstantProtocol {
        let offset: Duration

        func advanced(by duration: Duration) -> Self {
            Self(offset: offset + duration)
        }

        func duration(to other: Self) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    let timeline: VirtualTimeline

    var now: Instant { timeline.now }

    var minimumResolution: Duration { .zero }

    /// Suspends until the scheduler reaches `deadline`.
    ///
    /// A deadline that is not in the future returns at once, as it would on
    /// a real clock. Cancellation wakes the sleeper with `CancellationError`
    /// without moving time — a cancelled sleep costs nothing virtual.
    func sleep(until deadline: Instant, tolerance _: Duration? = nil) async throws {
        try Task.checkCancellation()
        let ticket = timeline.issueTicket()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                timeline.suspend(ticket, until: deadline, continuation)
            }
        } onCancel: {
            timeline.cancel(ticket)
        }
    }

    /// Suspends until every other task in the run is blocked, without moving
    /// time.
    ///
    /// A virtual sleep also waits for quiescence, but then moves `now`, which
    /// can wake a sleeper the caller meant to inspect while still asleep — a
    /// source parked "forever", say. `settle()` returns at the first moment
    /// the scheduler's queue is empty, before it would wake anyone, so what a
    /// lifetime law checks afterwards is what the run left behind, not what a
    /// later deadline undid. Cancellation does not cut it short: the wait
    /// already ends as soon as nothing else can run.
    ///
    /// Not for calling in a loop: the scheduler resumes settlers before it
    /// checks the horizon, so a task that only ever settles would keep the run
    /// from ending, and teardown resumes a bounded number of settles.
    func settle() async {
        await withCheckedContinuation { continuation in
            timeline.awaitSettle(continuation)
        }
    }
}
