import Foundation

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

    /// How many jobs a run may run before its verdict without the queue ever
    /// emptying. A lifetime-law trial reads at most 10,000 elements, a few jobs
    /// each, so only a task that re-enqueues itself forever comes near it.
    static let defaultStepLimit = 1_000_000
    /// How many jobs teardown may run, all rounds together. The verdict is
    /// decided before teardown, so this only bounds the clean-up: a livelock
    /// that outlives the verdict is abandoned, not run forever.
    static let teardownStepLimit = 10_000
    /// How many jobs the run's last drain may run, apart from teardown's, so a
    /// job handed back before the registry forgot the run still runs after a
    /// teardown that used up its own allowance.
    static let finalDrainStepLimit = 1_000

    private let queue: JobQueue<UnownedJob>
    private let stepLimit: Int
    /// What each phase may still run: the drive loop, teardown, the last drain.
    private var driveSteps: Int
    private var teardownSteps = VirtualTimeScheduler.teardownStepLimit
    private var finalSteps = VirtualTimeScheduler.finalDrainStepLimit
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

    init(
        order: JobOrder = .fifo,
        stepLimit: Int = VirtualTimeScheduler.defaultStepLimit,
        trace: ScheduleTrace? = nil
    ) {
        queue = JobQueue(order: order)
        self.stepLimit = stepLimit
        driveSteps = stepLimit
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
        queue.append(job)
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
        _ = drain(.final)
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
            if drain(.drive) == .stoppedAtLimit {
                // Escaped work can keep in-run code spinning while it waits;
                // the escape is the cause, as it is for any other verdict.
                failure = evidence.kind.map { .escaped(at: timeline.now.offset, evidence: $0) }
                    ?? .stepLimitExceeded(steps: stepLimit)
                break
            }
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
            if let stuck = advanceTime(horizon: horizon, hook: hook, timeline: timeline) {
                failure = stuck
                break
            }
        }
        trace?.markVerdict()
        tearDown(root, timeline)
        return .failure(failure)
    }

    /// Nothing in the run can go on: wake the earliest sleeper, or say why the
    /// run cannot go on. `nil` means go round the loop again.
    private func advanceTime(
        horizon: Duration?,
        hook: GlobalEnqueueHook,
        timeline: VirtualTimeline
    ) -> VirtualTimeError? {
        guard hook.isIntact else {
            return .foreignHookInstalled
        }
        guard let next = timeline.earliestDeadline else {
            // Only work outside the run can change anything now. Give it the
            // grace window to come back before calling this a deadlock.
            return awaitEvidence() ? nil : .deadlock(stuckAt: timeline.now.offset)
        }
        if let horizon, next.offset > horizon {
            return .horizonExceeded(horizon: horizon, nextDeadline: next.offset)
        }
        timeline.fireEarliest()
        return nil
    }

    /// The three phases that drain the queue, each with its own allowance.
    private enum Phase {
        case drive, teardown, final
    }

    private enum DrainEnd {
        /// The queue is empty: quiescence.
        case settled
        /// The phase's allowance ran out with jobs still pending.
        case stoppedAtLimit
    }

    /// Run every queued job, and every job those enqueue, until none remain or
    /// `phase`'s allowance runs out. A job that ends on the last step with the
    /// queue empty still settles. Outside the last drain, claim each job's task
    /// first, so the task is recognised if it ever comes back from another
    /// thread, and add the job to the trace.
    private func drain(_ phase: Phase) -> DrainEnd {
        while allowance(phase) > 0, let pick = queue.next() {
            spend(phase)
            if phase != .final {
                record(pick)
            }
            pick.job.runSynchronously(on: asUnownedSerialExecutor())
        }
        return queue.isEmpty ? .settled : .stoppedAtLimit
    }

    private func allowance(_ phase: Phase) -> Int {
        switch phase {
        case .drive: driveSteps
        case .teardown: teardownSteps
        case .final: finalSteps
        }
    }

    private func spend(_ phase: Phase) {
        switch phase {
        case .drive: driveSteps -= 1
        case .teardown: teardownSteps -= 1
        case .final: finalSteps -= 1
        }
    }

    private func record(_ pick: JobQueue<UnownedJob>.Pick) {
        let id = TaskIdentity.id(of: pick.job)
        if let id, seenIDs.insert(id).inserted {
            claim(id)
        }
        trace?.record(ScheduleTrace.Step(pending: pick.pending, picked: pick.picked, task: id.map(ordinal(of:))))
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

    /// End a run so that none of it outlives the scheduler: cancel the body
    /// (a no-op once it has returned), wake every sleeper with
    /// `CancellationError`, and let the tasks run out. Bounded in rounds,
    /// because a task that ignores cancellation and sleeps again would keep it
    /// going, and in steps (``teardownStepLimit``), because one that re-enqueues
    /// itself would too. A sleeper left after the rounds is leaked; jobs left
    /// when the steps run out are abandoned, never run, and an actor one of
    /// them held stays unusable.
    private func tearDown(_ root: Task<Void, Never>, _ timeline: VirtualTimeline) {
        root.cancel()
        for _ in 0 ..< 8 {
            guard drainAndSettle(timeline) == .settled, timeline.pendingSleeperCount > 0 else { return }
            timeline.cancelAll()
        }
        _ = drainAndSettle(timeline)
    }

    /// Drain, resuming `settle()` callers each time the queue empties, so a
    /// task that settles while being torn down is not left parked forever.
    /// Bounded like teardown itself; stops at once when its steps run out.
    private func drainAndSettle(_ timeline: VirtualTimeline) -> DrainEnd {
        for _ in 0 ..< 8 {
            guard drain(.teardown) == .settled else { return .stoppedAtLimit }
            guard timeline.resumeSettled() else { return .settled }
        }
        return drain(.teardown)
    }
}
