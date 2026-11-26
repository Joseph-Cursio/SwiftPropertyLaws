import Foundation

/// Run `body` against a ``VirtualClock`` on a private single-threaded
/// scheduler, and return what it returned.
///
/// Virtual time is only deterministic if time moves when — and only when —
/// every task is blocked. Nothing in Swift concurrency reports that, so a
/// clock driven from outside has to guess, and `TestClock` guesses by
/// yielding a fixed number of times. The scheduler removes the guess: every
/// job of the run executes on one thread it drains itself, so an empty queue
/// *is* quiescence. Only then does it wake the earliest sleeper.
///
/// A run cannot hang on scheduling. With the queue empty, the body unfinished
/// and nobody asleep, every task is waiting on something no task in the run
/// will do. The run then waits ``VirtualTimeScheduler/graceWindow`` of real
/// time for work from outside, and if none comes it reports
/// ``VirtualTimeError/deadlock(stuckAt:)`` rather than wait any longer. A
/// queue that never empties, because a task re-enqueues itself forever, ends
/// the run with ``VirtualTimeError/stepLimitExceeded(steps:)`` after
/// `stepLimit` jobs. A single job that never suspends is still beyond what the
/// scheduler can stop: it never hands the thread back.
///
/// **Order.** Under ``JobOrder/fifo`` jobs run in the order they were
/// enqueued. Under ``JobOrder/seeded(_:)`` each choice among two or more
/// pending jobs is drawn from the seed (``JobQueue`` has the exact rule), so
/// one seed is one interleaving, the same every time, provided nothing
/// outside the run adds jobs and the code under test does not iterate a
/// `Dictionary` or `Set` in an order that matters. Sleepers always wake at
/// quiescence, earliest deadline first and equal deadlines in the order they
/// went to sleep. `trace` records the order the jobs ran in.
///
/// **Contract.** Every job of the run must be created or resumed from inside
/// the run. A real `Task.sleep`, `MainActor`, an actor on a custom executor,
/// real I/O and callbacks from other threads take work out of the scheduler,
/// and `Task.yield()` inside an actor usually does. When that work shows
/// itself — a task of the run enqueued from another thread, the body
/// finishing on one, the clock used from one, or one of its tasks run by
/// another live run — the run ends with
/// ``VirtualTimeError/escaped(at:evidence:)``, whatever the body returned,
/// because virtual time may have moved while the work was away.
///
/// A task is the run's once one of its jobs has run in the run's queue, and
/// only if it was created after the run's root task (see ``RunRegistry``).
/// What is not seen:
/// - work that stays away past the grace window, which is why a deadlock's
///   message says it may be an escape;
/// - work still away when the body returns, since the run ends then;
/// - a task created before the run that it resumes: not the run's, so its
///   later trips away are left to the runtime;
/// - a task the run created whose jobs never reach its queue — started on
///   `MainActor` or another executor, or begun inside an actor's job and
///   leaving the actor without an enqueue — which is never the run's.
///
/// And one false escape: an outside task created after the run started and
/// resumed by it counts as the run's, so its own later trip away is blamed
/// on the run. Concurrent runs that share an actor can fail this way, or as
/// ``EscapeEvidence/Kind/sharedWithAnotherRun``, depending on timing.
///
/// - Parameter horizon: the furthest virtual time the run may reach. A run
///   whose next sleeper lies beyond it fails with
///   ``VirtualTimeError/horizonExceeded(horizon:nextDeadline:)`` instead of
///   advancing, so a pipeline that never settles is reported rather than
///   simulated forever.
func runInVirtualTime<Value: Sendable>(
    horizon: Duration? = nil,
    order: JobOrder = .fifo,
    stepLimit: Int = VirtualTimeScheduler.defaultStepLimit,
    trace: ScheduleTrace? = nil,
    _ body: @escaping @Sendable (VirtualClock) async throws -> Value
) async throws -> Value {
    // From inside a run, the outer body would be resumed from the inner
    // run's thread, escape the outer scheduler, and leave it reporting a
    // deadlock that is not one. Refused instead.
    guard VirtualTimeScheduler.current == nil else { throw VirtualTimeError.nestedRun }
    return try await withCheckedThrowingContinuation { continuation in
        // A thread of its own rather than a cooperative one: the run loop
        // blocks for the whole run, and a blocked pool thread is one the rest
        // of the process cannot use.
        let thread = Thread {
            let scheduler = VirtualTimeScheduler(order: order, stepLimit: stepLimit, trace: trace)
            continuation.resume(with: scheduler.run(horizon: horizon, body))
        }
        thread.start()
    }
}
