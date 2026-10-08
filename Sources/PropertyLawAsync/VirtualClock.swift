import Foundation

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

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
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
    func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
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
}

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
