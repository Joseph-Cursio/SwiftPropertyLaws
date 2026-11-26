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
/// asleep, every task is waiting on something no task in the run will do.
/// The run then waits ``VirtualTimeScheduler/graceWindow`` of real time for
/// work from outside, and if none comes it reports
/// ``VirtualTimeError/deadlock(stuckAt:)`` rather than wait any longer.
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
            continuation.resume(with: VirtualTimeScheduler(trace: trace).run(horizon: horizon, body))
        }
        thread.start()
    }
}

/// Why a virtual-time run ended without its body's result.
enum VirtualTimeError: Error, Equatable, CustomStringConvertible {
    /// Every task was blocked, nothing was asleep, and no work came back from
    /// outside the run within the grace window.
    case deadlock(stuckAt: Duration)
    /// Some of the run's work ran outside its scheduler, so its verdict
    /// cannot be trusted.
    case escaped(at: Duration, evidence: EscapeEvidence.Kind)
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
            return "virtual-time deadlock at \(now), or work that escaped the scheduler: every task is blocked, "
                + "none is sleeping on the clock, and nothing came back from outside the run within "
                + "\(VirtualTimeScheduler.graceWindow)"

        case let .escaped(now, evidence):
            return "work escaped the virtual-time scheduler by \(now): \(evidence). A real sleep, MainActor, "
                + "a custom executor, Task.yield() inside an actor or a callback from another thread can run "
                + "outside virtual time, so the run's result cannot be trusted"

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

/// The single-threaded executor behind ``runInVirtualTime(horizon:_:)``.
///
/// Every job a run creates reaches this queue one of two ways: a task the
/// run's own code spawns goes to the global executor, where
/// `GlobalEnqueueHook` diverts it here because it was enqueued from this
/// scheduler's thread; and anything it later resumes is enqueued from that
/// same thread, so it is diverted too. Jobs from every other thread pass
/// through untouched.
final class VirtualTimeScheduler: SerialExecutor, @unchecked Sendable {
    /// How long a run that looks deadlocked waits for work from outside before
    /// it says so. Escaped work that takes longer to come back is not seen.
    static let graceWindow: Duration = .milliseconds(100)

    private let lock = NSLock()
    private var jobs: [UnownedJob] = []
    private var head = 0
    private let evidence = EscapeEvidence()
    // Touched only on the run's own thread.
    /// The root task's ID. Task IDs only grow, so a task with a smaller one
    /// was created before the run and is not the run's.
    private var rootID: UInt64?
    /// Every task whose jobs this run has run, so each is claimed once.
    private var seenIDs: Set<UInt64> = []
    /// The tasks this run claimed in ``RunRegistry``, to forget at the end.
    private var ownedIDs: Set<UInt64> = []
    /// Where the run records the order it ran its jobs in, if anyone asked.
    private let trace: ScheduleTrace?
    /// Each task's ordinal within the run, in first-seen order, for the trace.
    private var ordinals: [UInt64: Int] = [:]

    init(trace: ScheduleTrace? = nil) {
        self.trace = trace
    }

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

    /// A job for this executor. From a thread outside the run, it is work
    /// coming back from wherever it escaped to.
    func enqueue(_ job: consuming ExecutorJob) {
        if Self.current !== self {
            evidence.record(.taskResumedFromOutside)
        }
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

    /// A task of this run, enqueued from another thread: back from wherever it
    /// escaped to. Run it here, and report the escape.
    func takeBack(_ job: UnownedJob) {
        evidence.record(.taskResumedFromOutside)
        schedule(job)
    }

    func noteEscape(_ kind: EscapeEvidence.Kind) {
        evidence.record(kind)
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
        let result = drive(horizon: horizon, hook: hook, body)
        // From here a task of this run enqueued from another thread goes to
        // the runtime. One handed back before the registry forgot it is still
        // queued; run it rather than strand it.
        RunRegistry.shared.forget(ownedIDs, of: self)
        drain(recording: false)
        return result
    }

    private func drive<Value: Sendable>(
        horizon: Duration?,
        hook: GlobalEnqueueHook,
        _ body: @escaping @Sendable (VirtualClock) async throws -> Value
    ) -> Result<Value, Error> {
        let timeline = VirtualTimeline(owner: self)
        let clock = VirtualClock(timeline: timeline)
        let outcome = RunOutcome<Value>()
        let root = Task {
            let result: Result<Value, Error>
            do {
                result = .success(try await body(clock))
            } catch {
                result = .failure(error)
            }
            // Before the result, so a run that sees the result also sees why
            // it cannot keep it.
            if Self.current !== self {
                self.evidence.record(.bodyFinishedOutside)
            }
            outcome.record(result)
        }
        let failure: VirtualTimeError
        while true {
            drain()
            // An empty queue is the moment `settle()` waits for: resume its
            // callers and run what they do next before anything else is
            // decided, so time moves only once they block again.
            if timeline.resumeSettled() {
                continue
            }
            // The result before the evidence: a body finishing on another
            // thread records its evidence first, so a result read here comes
            // with any evidence it carries.
            let finished = outcome.result
            if let kind = evidence.kind {
                failure = .escaped(at: timeline.now.offset, evidence: kind)
                break
            }
            if let result = finished {
                // The body is done, but a task it started may still be asleep.
                // Wake it with `CancellationError` rather than leave it parked
                // on a clock nobody will advance again.
                trace?.markVerdict()
                tearDown(root, timeline)
                return result
            }
            guard hook.isIntact else {
                failure = .foreignHookInstalled
                break
            }
            guard let next = timeline.earliestDeadline else {
                // Only work outside the run can change anything now. Give it
                // the grace window to come back before calling this a deadlock.
                if awaitEvidence() {
                    continue
                }
                failure = .deadlock(stuckAt: timeline.now.offset)
                break
            }
            if let horizon, next.offset > horizon {
                failure = .horizonExceeded(horizon: horizon, nextDeadline: next.offset)
                break
            }
            timeline.fireEarliest()
        }
        trace?.markVerdict()
        tearDown(root, timeline)
        return .failure(failure)
    }

    /// Run every queued job, and every job those enqueue, until none remain.
    /// While `recording`, claim each job's task first, so the task is
    /// recognised if it ever comes back from another thread, and add the job
    /// to the trace.
    private func drain(recording: Bool = true) {
        while let (job, pending, picked) = dequeue() {
            if recording {
                let id = TaskIdentity.id(of: job)
                if let id, seenIDs.insert(id).inserted {
                    claim(id)
                }
                if let trace {
                    trace.record(ScheduleTrace.Step(pending: pending, picked: picked, task: id.map(ordinal(of:))))
                }
            }
            job.runSynchronously(on: asUnownedSerialExecutor())
        }
    }

    private func ordinal(of id: UInt64) -> Int {
        if let known = ordinals[id] {
            return known
        }
        let next = ordinals.count
        ordinals[id] = next
        return next
    }

    /// Claim a task seen for the first time. The first job a run drains is
    /// its root's, since the root's is the first enqueued.
    private func claim(_ id: UInt64) {
        let floor = rootID ?? id
        rootID = floor
        switch RunRegistry.shared.claim(id, for: self, createdSince: floor) {
        case .claimed:
            ownedIDs.insert(id)

        case .createdBeforeTheRun:
            break

        case .ownedBy(let other):
            // The other run's work left it; this run's own did not. Blaming
            // this run too would depend on which of the other run's tasks
            // happened to reach this queue.
            other.noteEscape(.sharedWithAnotherRun)
        }
    }

    /// Wait up to ``graceWindow`` of real time for evidence of an escape.
    /// Every way work from outside can show itself — a job handed back or
    /// enqueued here, the body finishing, the clock used — records evidence
    /// before it changes anything else, so evidence is the one thing to watch.
    /// Polls, because a run that reaches here is already a failure.
    private func awaitEvidence() -> Bool {
        let giveUp = ContinuousClock.now.advanced(by: Self.graceWindow)
        while evidence.kind == nil {
            guard ContinuousClock.now < giveUp else { return false }
            Thread.sleep(forTimeInterval: 0.001)
        }
        return true
    }

    /// The next job, how many were pending, and its position among them.
    private func dequeue() -> (job: UnownedJob, pending: Int, picked: Int)? {
        lock.lock()
        defer { lock.unlock() }
        guard head < jobs.count else {
            jobs.removeAll(keepingCapacity: true)
            head = 0
            return nil
        }
        let pending = jobs.count - head
        let job = jobs[head]
        head += 1
        return (job, pending, 0)
    }

    /// End a run so that none of it outlives the scheduler: cancel the body
    /// (a no-op once it has returned), wake every sleeper with
    /// `CancellationError`, and let the tasks run out. Bounded, because a
    /// task that ignores cancellation and sleeps again would keep it going;
    /// whatever is left after the rounds is leaked.
    private func tearDown(_ root: Task<Void, Never>, _ timeline: VirtualTimeline) {
        root.cancel()
        for _ in 0 ..< 8 {
            drainAndSettle(timeline)
            guard timeline.pendingSleeperCount > 0 else { return }
            timeline.cancelAll()
        }
        drainAndSettle(timeline)
    }

    /// Drain, resuming `settle()` callers each time the queue empties, so a
    /// task that settles while being torn down is not left parked forever.
    /// Bounded like teardown itself.
    private func drainAndSettle(_ timeline: VirtualTimeline) {
        for _ in 0 ..< 8 {
            drain()
            guard timeline.resumeSettled() else { return }
        }
        drain()
    }
}
