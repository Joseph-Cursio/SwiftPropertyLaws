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
/// A run cannot hang. With the queue empty, the body unfinished and nobody
/// asleep, every task is waiting on something no task will do; that is
/// reported as ``VirtualTimeError/deadlock(stuckAt:)`` rather than awaited.
///
/// **Contract.** Every job of the run must be created or resumed from inside
/// the run. Real I/O, wall-clock sleeps and callbacks from other threads
/// escape the scheduler, and a run that depends on them will be judged
/// quiescent while they are still pending.
///
/// - Parameter horizon: the furthest virtual time the run may reach. A run
///   whose next sleeper lies beyond it fails with
///   ``VirtualTimeError/horizonExceeded(horizon:nextDeadline:)`` instead of
///   advancing, so a pipeline that never settles is reported rather than
///   simulated forever.
func runInVirtualTime<Value: Sendable>(
    horizon: Duration? = nil,
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
            continuation.resume(with: VirtualTimeScheduler().run(horizon: horizon, body))
        }
        thread.start()
    }
}

/// Why a virtual-time run ended without its body's result.
enum VirtualTimeError: Error, Equatable, CustomStringConvertible {
    /// Every task was blocked and nothing was asleep, so nothing could ever
    /// run again.
    case deadlock(stuckAt: Duration)
    /// The next sleeper's deadline lies beyond the run's horizon.
    case horizonExceeded(horizon: Duration, nextDeadline: Duration)
    /// The runtime's global enqueue hook could not be found.
    case hookUnavailable
    /// Another global enqueue hook was installed — `withMainSerialExecutor`,
    /// for one — so this run cannot see its own tasks.
    case foreignHookInstalled
    /// `runInVirtualTime` was called from inside a run. Runs do not nest.
    case nestedRun

    var description: String {
        switch self {
        case .deadlock(let now):
            return "virtual-time deadlock at \(now): every task is blocked and "
                + "none is sleeping on the clock"
        case let .horizonExceeded(horizon, nextDeadline):
            return "virtual time would pass its horizon of \(horizon): the next "
                + "sleeper wakes at \(nextDeadline)"
        case .hookUnavailable:
            return "the Swift runtime's global enqueue hook was not found, so "
                + "virtual time cannot capture the tasks under test"
        case .foreignHookInstalled:
            return "another global enqueue hook is installed (is this running "
                + "inside withMainSerialExecutor?); virtual time cannot share it"
        case .nestedRun:
            return "runInVirtualTime was called from inside a virtual-time run; "
                + "runs do not nest"
        }
    }
}

/// The single-threaded executor behind ``runInVirtualTime(horizon:_:)``.
///
/// Every job a run creates reaches this queue one of two ways: a task the
/// run's own code spawns goes to the global executor, where
/// `GlobalEnqueueHook` diverts it here because it was enqueued from this
/// scheduler's thread; and anything it later resumes is enqueued from that
/// same thread, so it is diverted too. Jobs from every other thread pass
/// through untouched.
final class VirtualTimeScheduler: SerialExecutor, @unchecked Sendable {
    private let lock = NSLock()
    private var jobs: [UnownedJob] = []
    private var head = 0

    /// The scheduler that owns the calling thread, if any. Read by the
    /// enqueue hook on every global enqueue in the process.
    static var current: VirtualTimeScheduler? {
        pthread_getspecific(threadKey).map {
            Unmanaged<VirtualTimeScheduler>.fromOpaque($0).takeUnretainedValue()
        }
    }

    private static let threadKey: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key, nil)
        return key
    }()

    func enqueue(_ job: consuming ExecutorJob) {
        schedule(UnownedJob(job))
    }

    func schedule(_ job: UnownedJob) {
        lock.lock()
        jobs.append(job)
        lock.unlock()
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }

    /// Run `body` to completion on the calling thread, which this scheduler
    /// owns for the duration.
    func run<Value: Sendable>(
        horizon: Duration?,
        hook: GlobalEnqueueHook = .shared,
        _ body: @escaping @Sendable (VirtualClock) async throws -> Value
    ) -> Result<Value, Error> {
        do {
            try hook.acquire()
        } catch {
            return .failure(error)
        }
        defer { hook.release() }
        pthread_setspecific(Self.threadKey, Unmanaged.passUnretained(self).toOpaque())
        // Cleared before returning, so the caller's continuation — resumed
        // from this thread once `run` is done — is not diverted into a queue
        // nobody will drain again.
        defer { pthread_setspecific(Self.threadKey, nil) }
        return drive(horizon: horizon, hook: hook, body)
    }

    private func drive<Value: Sendable>(
        horizon: Duration?,
        hook: GlobalEnqueueHook,
        _ body: @escaping @Sendable (VirtualClock) async throws -> Value
    ) -> Result<Value, Error> {
        let timeline = VirtualTimeline()
        let clock = VirtualClock(timeline: timeline)
        let outcome = RunOutcome<Value>()
        let root = Task {
            do {
                outcome.record(.success(try await body(clock)))
            } catch {
                outcome.record(.failure(error))
            }
        }
        let failure: VirtualTimeError
        while true {
            drain()
            if let result = outcome.result {
                // The body is done, but a task it started may still be asleep.
                // Wake it with `CancellationError` rather than leave it parked
                // on a clock nobody will advance again.
                tearDown(root, timeline)
                return result
            }
            guard hook.isIntact else {
                failure = .foreignHookInstalled
                break
            }
            guard let next = timeline.earliestDeadline else {
                failure = .deadlock(stuckAt: timeline.now.offset)
                break
            }
            if let horizon, next.offset > horizon {
                failure = .horizonExceeded(horizon: horizon, nextDeadline: next.offset)
                break
            }
            timeline.fireEarliest()
        }
        tearDown(root, timeline)
        return .failure(failure)
    }

    /// Run every queued job, and every job those enqueue, until none remain.
    private func drain() {
        while let job = dequeue() {
            job.runSynchronously(on: asUnownedSerialExecutor())
        }
    }

    private func dequeue() -> UnownedJob? {
        lock.lock()
        defer { lock.unlock() }
        guard head < jobs.count else {
            jobs.removeAll(keepingCapacity: true)
            head = 0
            return nil
        }
        let job = jobs[head]
        head += 1
        return job
    }

    /// End a run so that none of it outlives the scheduler: cancel the body
    /// (a no-op once it has returned), wake every sleeper with
    /// `CancellationError`, and let the tasks run out. Bounded, because a
    /// task that ignores cancellation and sleeps again would keep it going;
    /// whatever is left after the rounds is leaked.
    private func tearDown(_ root: Task<Void, Never>, _ timeline: VirtualTimeline) {
        root.cancel()
        for _ in 0 ..< 8 {
            drain()
            guard timeline.pendingSleeperCount > 0 else { return }
            timeline.cancelAll()
        }
        drain()
    }
}

/// The body's result, set once from inside the run.
private final class RunOutcome<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<Value, Error>?

    var result: Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func record(_ result: Result<Value, Error>) {
        lock.lock()
        stored = result
        lock.unlock()
    }
}
