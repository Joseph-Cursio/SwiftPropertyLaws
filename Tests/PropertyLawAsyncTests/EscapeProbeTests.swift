import Foundation
@testable import PropertyLawAsync
import Testing

/// A serial executor that runs each job on a Dispatch queue. Written out
/// rather than `DispatchSerialQueue`, which Linux's Dispatch lacks.
private final class QueueExecutor: SerialExecutor {
    private let queue = DispatchQueue(label: "PropertyLawAsyncTests.QueueExecutor")

    func enqueue(_ job: consuming ExecutorJob) {
        let unowned = UnownedJob(job)
        queue.async {
            unowned.runSynchronously(on: self.asUnownedSerialExecutor())
        }
    }

    func asUnownedSerialExecutor() -> UnownedSerialExecutor {
        UnownedSerialExecutor(ordinary: self)
    }
}

/// An actor whose jobs run on a Dispatch queue, not on whichever executor
/// called it: a custom executor, which the global enqueue hook never sees.
private actor QueueBoundActor {
    private let executor = QueueExecutor()

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        executor.asUnownedSerialExecutor()
    }

    func touch() -> Int {
        1
    }
}

/// A default actor whose method yields while isolated to it, and says
/// whether it came back on the run's thread.
private actor YieldingCounter {
    private var value = 0

    func incrementStayingInTheRun() async -> Bool {
        value += 1
        await Task.yield()
        return VirtualTimeScheduler.current != nil
    }
}

/// A default actor that starts a task isolated to itself, which leaves the
/// actor without an enqueue.
private actor ActorStartedWorker {
    private var started = 0

    func start(_ work: @escaping @Sendable () async -> Void) {
        Task {
            started += 1
            await work()
        }
    }
}

/// A default actor, which runs on whichever executor its callers use.
private actor Counter {
    private var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

/// A real wait that each escaping probe makes, well inside the grace window.
private let probeWait = Duration.milliseconds(10)

/// The five escapes the schedule-explorer prototype reported as deadlocks
/// (`docs/async-plan.md` M2 in the umbrella prototype), and a default actor,
/// which stays in the run. Each probe's work leaves the scheduler and comes
/// back inside the grace window, so the run must say it escaped; one that
/// stays away longer is a deadlock that says it may be an escape.
struct EscapeProbeTests {
    /// How the sleeper comes back depends on the runtime. On Swift 6.4 its
    /// wake-up is a global enqueue from a Dispatch thread, so the hook hands it
    /// back; a runtime that runs the woken job on Dispatch directly would let
    /// the body finish there instead. Either is an escape.
    @Test func aRealSleepIsReportedAsAnEscape() async throws {
        let ended = try await escapingVerdict { _ in
            try await Task.sleep(for: probeWait)
            return 1
        }
        switch ended {
        case .failure(.escaped(_, evidence: .taskResumedFromOutside)),
             .failure(.escaped(_, evidence: .bodyFinishedOutside)):
            break

        default:
            Issue.record("expected an escape, got \(ended)")
        }
    }

    @Test func mainActorWorkIsReportedAsAnEscape() async throws {
        let ended = try await escapingVerdict { _ in
            await MainActor.run { 1 }
        }
        guard case .failure(.escaped(_, evidence: .taskResumedFromOutside)) = ended else {
            Issue.record("expected an escape seen as a task resumed from outside, got \(ended)")
            return
        }
    }

    @Test func anActorOnACustomExecutorIsReportedAsAnEscape() async throws {
        let actor = QueueBoundActor()
        let ended = try await escapingVerdict { _ in
            await actor.touch()
        }
        guard case .failure(.escaped(_, evidence: .taskResumedFromOutside)) = ended else {
            Issue.record("expected an escape seen as a task resumed from outside, got \(ended)")
            return
        }
    }

    /// The body would return 1 if the run kept its result; an escape
    /// discards it.
    @Test func aContinuationResumedByDispatchIsReportedAsAnEscape() async throws {
        let ended = try await escapingVerdict { _ in
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                outsideQueue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                    continuation.resume(returning: 1)
                }
            }
        }
        guard case .failure(.escaped(_, evidence: .taskResumedFromOutside)) = ended else {
            Issue.record("expected an escape seen as a task resumed from outside, got \(ended)")
            return
        }
    }

    /// Away for longer than the grace window, so nothing is seen in time. The
    /// run waits out the window, then says deadlock, and its message says it
    /// may be an escape.
    @Test func workAwayLongerThanTheGraceWindowIsADeadlockThatSaysItMayBeAnEscape() async throws {
        let start = ContinuousClock.now
        let ended = try await verdict { _ in
            try await Task.sleep(for: .seconds(1))
            return 1
        }
        #expect(ContinuousClock.now - start >= VirtualTimeScheduler.graceWindow)
        guard case .failure(let error) = ended, error == .deadlock(stuckAt: .zero) else {
            Issue.record("expected a deadlock at zero, got \(ended)")
            return
        }
        #expect(error.description.contains("or work that escaped the scheduler"), "\(error)")
        #expect(error.description.contains("\(VirtualTimeScheduler.graceWindow)"), "\(error)")
    }

    /// A task started from a Dispatch thread is not the run's, so it runs on
    /// the global pool; when it sleeps on the run's clock, that is the sign.
    @Test func theClockUsedFromAnotherThreadIsReportedAsAnEscape() async throws {
        let ended = try await escapingVerdict { clock in
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                outsideQueue.async {
                    Task {
                        try? await clock.sleep(for: .seconds(1))
                        continuation.resume(returning: 1)
                    }
                }
            }
        }
        guard case .failure(.escaped(_, evidence: .clockUsedFromOutside)) = ended else {
            Issue.record("expected an escape seen as the clock used from outside, got \(ended)")
            return
        }
    }

    /// `Task.yield()` inside an actor-isolated method usually sends its job to
    /// the runtime's default executor without passing the hook, so it is an
    /// escape even though the actor itself is a default one. Under load the
    /// actor sometimes keeps the job on the run's thread, and the run may then
    /// keep its result; it must never keep one from work that left.
    @Test func aYieldInsideAnActorIsReportedAsAnEscape() async throws {
        let ended = try await escapingVerdict { _ in
            await YieldingCounter().incrementStayingInTheRun()
        }
        switch ended {
        case .failure(.escaped), .success(true):
            break

        default:
            Issue.record("expected an escape, or a result from work that stayed in the run, got \(ended)")
        }
    }

    /// A known limit: a task the run starts on a default actor runs inside
    /// the actor's processing job, which belongs to no task, and, while the
    /// body waits on another task, leaves the actor without an enqueue, so the
    /// run never claims it. When it waits on Dispatch, it comes back on the
    /// runtime and the run is not told.
    @Test func aTaskStartedOnAnActorThatEscapesIsNotSeen() async throws {
        let worker = ActorStartedWorker()
        let done = Latch()
        let ended = try await verdict { _ in
            await worker.start {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    outsideQueue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                        continuation.resume()
                    }
                }
                done.set()
            }
            await Task {}.value
            let giveUp = ContinuousClock.now.advanced(by: patience)
            while !done.isSet, ContinuousClock.now < giveUp {
                await yieldAndRest()
            }
            return done.isSet
        }
        #expect(ended == .success(true), "\(ended)")
    }

    /// A known limit: a task the body leaves behind that is away when the
    /// body returns is not seen, because the run ends there.
    @Test func workStillAwayWhenTheBodyReturnsIsNotSeen() async throws {
        let ended = try await verdict { _ in
            Task {
                try? await Task.sleep(for: probeWait)
            }
            return 1
        }
        #expect(ended == .success(1))
    }

    /// An outside task the run resumes is not the run's: when it later leaves
    /// for Dispatch in its own code, the run is not blamed. The task must be
    /// waiting on the stream when the run yields, or it reads the buffered
    /// element on its own and the run never resumes it; `resumedInTheRun`
    /// checks that the path was taken.
    @Test func anOutsideTaskTheRunResumesIsNotTheRuns() async throws {
        let (stream, continuation) = AsyncStream<Int>.makeStream()
        let started = Latch()
        let resumedInTheRun = Latch()
        let done = Latch()
        let outside = Task.detached {
            started.set()
            for await _ in stream {
                if VirtualTimeScheduler.current != nil {
                    resumedInTheRun.set()
                }
                break
            }
            await withCheckedContinuation { (resume: CheckedContinuation<Void, Never>) in
                outsideQueue.asyncAfter(deadline: .now() + .milliseconds(2)) {
                    resume.resume()
                }
            }
            done.set()
        }
        #expect(try await started.isSet(within: patience))
        try await Task.sleep(for: .milliseconds(10))
        let ended = try await verdict { _ in
            continuation.yield(1)
            let giveUp = ContinuousClock.now.advanced(by: patience)
            while !done.isSet, ContinuousClock.now < giveUp {
                await yieldAndRest()
            }
            return done.isSet
        }
        await outside.value
        #expect(ended == .success(true), "\(ended)")
        #expect(resumedInTheRun.isSet, "the outside task read the element without the run resuming it")
    }

    @Test func aDefaultActorStaysInTheRun() async throws {
        let ended = try await verdict { _ in
            let counter = Counter()
            async let first = counter.increment()
            async let second = counter.increment()
            return await [first, second].sorted()
        }
        #expect(ended == .success([1, 2]))
    }
}
