import Foundation
@testable import PropertyLawAsync
import Testing

/// Long enough after a run reaches its grace window that the run is surely
/// polling, and well inside the window.
private let insideTheGraceWindow = DispatchTimeInterval.milliseconds(20)

/// Well past the grace window.
private let pastTheGraceWindow = DispatchTimeInterval.milliseconds(300)

/// Hold the calling thread, which for a run's body is the run's own thread.
private func blockThisThread(seconds: TimeInterval) {
    Thread.sleep(forTimeInterval: seconds)
}

/// The escape-detection paths the probes in ``EscapeProbeTests`` leave
/// unchecked: each test pins one way the detection could quietly break.
struct EscapeDetectionTests {
    /// A task the run left parked, resumed by Dispatch once the run is over,
    /// belongs to no live run, so it goes to the runtime and runs. A registry
    /// that still mapped it would hand it to a scheduler nobody drains.
    @Test func aTaskComingBackAfterItsRunEndedRunsOnTheRuntime() async throws {
        let ran = Latch()
        let ended = try await verdict { _ in
            Task {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    outsideQueue.asyncAfter(deadline: .now() + insideTheGraceWindow) {
                        continuation.resume()
                    }
                }
                ran.set()
            }
            return 1
        }
        #expect(ended == .success(1))
        #expect(try await ran.isSet(within: patience), "the task was stranded in the ended run")
    }

    /// A task from outside the run that calls an actor on the run's own
    /// executor reaches the scheduler's `enqueue(_:)` from another thread.
    @Test func workEnqueuedOnTheSchedulerFromOutsideIsReportedAsAnEscape() async throws {
        let ended = try await escapingVerdict { _ in
            let scheduler = try #require(VirtualTimeScheduler.current)
            let actor = SchedulerBoundActor(scheduler: scheduler)
            return await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                outsideQueue.asyncAfter(deadline: .now() + insideTheGraceWindow) {
                    Task {
                        continuation.resume(returning: await actor.touch())
                    }
                }
            }
        }
        guard case .failure(let error) = ended,
              case .escaped(_, evidence: .taskResumedFromOutside) = error
        else {
            Issue.record("expected an escape seen as a task resumed from outside, got \(ended)")
            return
        }
        #expect(error.description.contains(EscapeEvidence.Kind.taskResumedFromOutside.description), "\(error)")
    }

    /// A sleep from outside the run whose deadline has already passed leaves
    /// no sleeper; the evidence it records is the only sign. The body is
    /// resumed only after the grace window, so nothing else shows in time.
    @Test func aSleepFromOutsideThatLeavesNoSleeperIsStillAnEscape() async throws {
        let ended = try await escapingVerdict { clock in
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                outsideQueue.asyncAfter(deadline: .now() + insideTheGraceWindow) {
                    Task {
                        try? await clock.sleep(until: clock.now)
                        outsideQueue.asyncAfter(deadline: .now() + pastTheGraceWindow) {
                            continuation.resume(returning: 1)
                        }
                    }
                }
            }
        }
        guard case .failure(.escaped(_, evidence: .clockUsedFromOutside)) = ended else {
            Issue.record("expected an escape seen as the clock used from outside, got \(ended)")
            return
        }
    }

    /// `settle()` from outside the run is the clock used from outside, as a
    /// sleep is, not just work that arrived.
    @Test func aSettleFromOutsideIsReportedAsTheClockUsedFromOutside() async throws {
        let ended = try await escapingVerdict { clock in
            await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                outsideQueue.asyncAfter(deadline: .now() + insideTheGraceWindow) {
                    Task {
                        await clock.settle()
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

    /// The body waits on a default actor held by a task outside the run. When
    /// the holder lets go, the actor's processing job, which belongs to no
    /// task, runs the body's call on the runtime, and the body carries on and
    /// finishes there, with no task of the run's enqueued for the hook to hand
    /// back. That job needs a pool thread inside the grace window, so a run
    /// that missed it is set up again until ``patience`` runs out.
    @Test func aBodyThatFinishesOnAnotherThreadIsReportedAsSuch() async throws {
        let giveUp = ContinuousClock.now.advanced(by: patience)
        var ended: Result<Int, VirtualTimeError>
        repeat {
            let actor = HeldActor()
            let holding = Latch()
            let reached = Latch()
            let holder = Task.detached {
                await actor.hold(holding: holding, until: reached, thenFor: 0.03)
            }
            #expect(try await holding.isSet(within: patience))
            ended = try await verdict { _ in
                reached.set()
                return await actor.touch()
            }
            await holder.value
        } while ended == .failure(.deadlock(stuckAt: .zero)) && ContinuousClock.now < giveUp
        guard case .failure(.escaped(_, evidence: .bodyFinishedOutside)) = ended else {
            Issue.record("expected an escape seen as the body finishing outside, got \(ended)")
            return
        }
    }

    /// The job handed back is run before the run returns, even though the
    /// run already knows it escaped: the code after the escape still runs.
    @Test func aTaskHandedBackRunsBeforeTheRunReturns() async throws {
        let resumed = Latch()
        let ended = try await escapingVerdict { _ in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                outsideQueue.asyncAfter(deadline: .now() + insideTheGraceWindow) {
                    continuation.resume()
                }
            }
            resumed.set()
            return 1
        }
        guard case .failure(.escaped(_, evidence: .taskResumedFromOutside)) = ended else {
            Issue.record("expected an escape seen as a task resumed from outside, got \(ended)")
            return
        }
        #expect(resumed.isSet, "the job handed back was stranded")
    }

    /// An actor's processing job belongs to no task. A run that ran one must
    /// not claim the next one enqueued from outside, here while the body
    /// holds the run's thread. The outside task needs a pool thread, so the
    /// body holds the run until the outside call is under way; a run that
    /// ended first would pass without testing anything.
    @Test func aJobOfNoTaskFromOutsideIsNotClaimedByTheRun() async throws {
        let inside = IsolatedTaskSpawner()
        let outside = IsolatedTaskSpawner()
        let calling = Latch()
        let spawned = Latch()
        let ended = try await verdict { _ in
            await inside.spawn()
            outsideQueue.async {
                Task.detached {
                    calling.set()
                    await outside.spawn()
                    spawned.set()
                }
            }
            let giveUp = ContinuousClock.now.advanced(by: patience)
            while !calling.isSet, ContinuousClock.now < giveUp {
                restThisThread()
            }
            blockThisThread(seconds: 0.05)
            return calling.isSet
        }
        #expect(ended == .success(true), "\(ended)")
        #expect(try await spawned.isSet(within: patience))
    }

    /// The lifetime laws report an operator whose work leaves virtual time as
    /// escaping, not as a hang or a bare scheduler error.
    /// A MainActor trip that outlasts the grace window under load is a hang
    /// instead, so a check whose only other counterexamples are hangs runs
    /// again until ``patience`` runs out, as `escapingVerdict` does for a
    /// deadlock. Any other counterexample fails at once.
    @Test func anOperatorThatEscapesFailsTheLifetimeLawsAsAnEscape() async throws {
        let giveUp = ContinuousClock.now.advanced(by: patience)
        var failed: [AsyncLifetimeLaw: String] = [:]
        var settled = false
        while !settled {
            failed = try await LifetimeLawResults.failures { source, _ in
                MainActorHopSequence(base: source)
            }
            let onlyHangsLeft = failed.values.allSatisfy { $0.contains("escaped:") || $0.hasPrefix("hang:") }
            let allEscaped = failed.values.allSatisfy { $0.contains("escaped:") }
            settled = allEscaped || !onlyHangsLeft || ContinuousClock.now >= giveUp
        }
        #expect(!failed.isEmpty)
        for (law, counterexample) in failed {
            #expect(counterexample.contains("escaped:"), "\(law): \(counterexample)")
        }
    }

    /// Run B resumes a task of run A from B's own thread, so the task runs in
    /// B. A's work left A, so A cannot trust its verdict; B's own work stayed
    /// home, so B keeps its result. A spins on the task's flag rather than
    /// wait, so it is still live when B sees the task, however late B starts.
    @Test func aTaskPassedToAnotherRunIsAnEscapeOfItsOwnRun() async throws {
        let taskOfA = ContinuationSlot()
        let ranInB = Latch()
        let runA = Task {
            try await verdict { _ in
                Task {
                    await taskOfA.park()
                    ranInB.set()
                }
                let giveUp = ContinuousClock.now.advanced(by: patience)
                while !ranInB.isSet, ContinuousClock.now < giveUp {
                    await yieldAndRest()
                }
                return 1
            }
        }
        #expect(try await taskOfA.stored.isSet(within: patience))
        let endedB = try await verdict { _ in
            taskOfA.resume()
            return 2
        }
        let endedA = try await runA.value
        #expect(endedB == .success(2))
        guard case .failure(.escaped(_, evidence: .sharedWithAnotherRun)) = endedA else {
            Issue.record("expected run A to report its task ran in another run, got \(endedA)")
            return
        }
    }

    /// Run B resumes a task of run A, then the task waits on Dispatch and is
    /// resumed from outside once B has ended. The first live run to claim a
    /// task keeps it, so the task comes back to A and runs there, not on the
    /// runtime.
    @Test func aTaskPassedToAnotherRunStaysWithTheRunThatClaimedItFirst() async throws {
        let first = ContinuationSlot()
        let second = ContinuationSlot()
        let finished = Latch()
        let ranInA = Latch()
        let runA = Task {
            try await verdict { _ in
                let runA = try #require(VirtualTimeScheduler.current)
                Task {
                    await first.park()
                    await second.park()
                    if VirtualTimeScheduler.current === runA {
                        ranInA.set()
                    }
                    finished.set()
                }
                let giveUp = ContinuousClock.now.advanced(by: patience)
                while !finished.isSet, ContinuousClock.now < giveUp {
                    await yieldAndRest()
                }
                return 1
            }
        }
        #expect(try await first.stored.isSet(within: patience))
        _ = try await verdict { _ in
            first.resume()
            return 2
        }
        #expect(second.stored.isSet, "the task did not reach its second wait inside run B")
        second.resume()
        _ = try await runA.value
        #expect(ranInA.isSet, "the task did not come back to the run that claimed it first")
    }

    /// A task that starts on a default actor runs its first job inside the
    /// actor's processing job, which belongs to no task, so the run first
    /// sees its ID when it is resumed, after a task created later. It is
    /// still the run's: when it then waits on Dispatch, its return is an
    /// escape.
    @Test func aTaskFirstSeenAfterALaterOneIsStillTheRuns() async throws {
        let starter = ActorStartedTask()
        let slot = ContinuationSlot()
        let done = Latch()
        let ended = try await verdict { _ in
            await starter.start(parkingIn: slot) {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    outsideQueue.asyncAfter(deadline: .now() + .milliseconds(10)) {
                        continuation.resume()
                    }
                }
                done.set()
            }
            await Task {}.value
            while !slot.stored.isSet {
                await Task.yield()
            }
            slot.resume()
            let giveUp = ContinuousClock.now.advanced(by: patience)
            while !done.isSet, ContinuousClock.now < giveUp {
                await yieldAndRest()
            }
            return done.isSet
        }
        guard case .failure(.escaped(_, evidence: .taskResumedFromOutside)) = ended else {
            Issue.record("expected an escape seen as a task resumed from outside, got \(ended)")
            return
        }
    }
}
