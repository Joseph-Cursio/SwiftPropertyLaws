import PropertyBased
@testable import PropertyLawAsync
import PropertyLawKit
import Testing

/// The lifetime laws over planted operators only (async-plan decision 2):
/// two correct operators that every law must pass, and one planted defect
/// per law that must fail that law and no other. The one exception is the
/// defect that keeps its upstream after the iterator goes: it leaks whichever
/// goes last, so it fails both release laws. The real swift-async-algorithms
/// operators are checked outside this package, against pinned revisions,
/// because the release this package resolves still has the bugs the defects
/// model.
struct AsyncLifetimeLawsTests {
    @Test func identityPassesEveryLifetimeLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in source }
        #expect(failed.isEmpty, "\(failed)")
    }

    @Test func taskBackedForwardingOperatorPassesEveryLifetimeLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, clock in
            ForwardingSequence(base: source, defect: .correct, delay: (clock, .milliseconds(5)))
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// It never stops its producer when the iterator goes, so dropping the
    /// sequence afterwards leaks too: both release laws fail, and no other.
    @Test func keepingUpstreamAfterTheIteratorIsDroppedFailsOnlyTheReleaseLaws() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source, defect: .keepsUpstreamAfterDrop)
        }
        #expect(
            Set(failed.keys) == [.releasesUpstreamWhenConsumerLeaves, .releasesUpstreamWhenSequenceDroppedLast],
            "\(failed)"
        )
        #expect(failed[.releasesUpstreamWhenConsumerLeaves]?.contains("never released") == true)
        #expect(failed[.releasesUpstreamWhenSequenceDroppedLast]?.contains("then the sequence") == true)
    }

    @Test func forgettingUpstreamOnACancelledNextFailsOnlyTheCancellationLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source, defect: .forgetsUpstreamOnCancelledNext)
        }
        #expect(Set(failed.keys) == [.cancellationReachesUpstream], "\(failed)")
        #expect(failed[.cancellationReachesUpstream]?.contains("never released") == true)
    }

    @Test func droppingAFailureWithoutDemandFailsOnlyTheFailureLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source, defect: .dropsFailureWithoutDemand)
        }
        #expect(Set(failed.keys) == [.failureReachesConsumerWithoutDemand], "\(failed)")
        #expect(
            failed[.failureReachesConsumerWithoutDemand]?.contains("finished without delivering it") == true
        )
    }

    @Test func restartingAfterTheEndFailsOnlyTheFinishedLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in RestartingSequence(base: source) }
        #expect(Set(failed.keys) == [.finishedStaysFinished], "\(failed)")
        #expect(failed[.finishedStaysFinished]?.contains("after it had finished") == true)
    }

    /// A consumer that waits forever is reported as a hang, not awaited.
    @Test func ignoringCancellationInNextIsReportedAsAHang() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source, defect: .ignoresCancellationInNext)
        }
        #expect(Set(failed.keys) == [.cancellationReachesUpstream], "\(failed)")
        #expect(failed[.cancellationReachesUpstream]?.contains("hang:") == true)
    }

    /// The pause outside `next()` matters: this defect forgets the producer
    /// only once elements are queued, which the pause lets happen.
    @Test func forgettingUpstreamOnlyWhenElementsAreQueuedFailsTheCancellationLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source, defect: .forgetsUpstreamOnCancelledNextWhenQueued)
        }
        #expect(Set(failed.keys) == [.cancellationReachesUpstream], "\(failed)")
    }

    @Test func anOperatorThatEmitsMoreThanItReceivesPassesEveryLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in DoublingSequence(base: source) }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// `prefix` stops reading before the source fails, so it owes no failure.
    @Test func anOperatorThatStopsReadingEarlyPassesEveryLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in source.prefix(1) }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// An operator that never emits leaves the consumer waiting; the laws cancel
    /// it at the deadline rather than reporting a hang.
    @Test func anOperatorThatNeverEmitsPassesEveryLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in source.filter { _ in false } }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// A release that takes a few scheduler hops after the drop is still a
    /// release: the laws settle the run before they look.
    @Test func aReleaseAFewHopsAfterTheDropPassesEveryLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in SlowReleaseSequence(base: source) }
        #expect(failed.isEmpty, "\(failed)")
        let silent = try await LifetimeLawResults.failures { source, _ in
            SlowReleaseSequence(base: source.filter { _ in false })
        }
        #expect(silent.isEmpty, "\(silent)")
    }

    @Test func leakingOneOfTwoUpstreamIteratorsFailsTheReleaseLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            LeaksASecondIteratorSequence(base: source)
        }
        #expect(failed[.releasesUpstreamWhenConsumerLeaves]?.contains("1 of the 2") == true, "\(failed)")
    }

    @Test func replacingTheUpstreamFailureFailsTheFailureLaw() async throws {
        for immediately in [false, true] {
            let failed = try await LifetimeLawResults.failures { source, _ in
                ReplacesFailureSequence(base: source, immediately: immediately)
            }
            #expect(
                failed[.failureReachesConsumerWithoutDemand]?.contains("instead of the upstream failure") == true,
                "immediately: \(immediately); \(failed)"
            )
        }
    }

    @Test func swallowingTheUpstreamFailureFailsTheFailureLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in SwallowsFailureSequence(base: source) }
        #expect(
            failed[.failureReachesConsumerWithoutDemand]?.contains("finished without delivering it") == true,
            "\(failed)"
        )
        let silent = try await LifetimeLawResults.failures { source, _ in
            SwallowsFailureSequence(base: source.filter { _ in false })
        }
        #expect(
            silent[.failureReachesConsumerWithoutDemand]?.contains("finished without delivering it") == true,
            "\(silent)"
        )
    }

    @Test func emittingForeverFailsTheFailureAndFinishedLaws() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in EmitsForeverSequence(base: source) }
        #expect(
            failed[.failureReachesConsumerWithoutDemand]?.contains("after the upstream failed, the law's cap") == true,
            "\(failed)"
        )
        #expect(failed[.finishedStaysFinished]?.contains("without finishing, the law's cap") == true, "\(failed)")
    }

    @Test func restartingOnTheThirdCallAfterTheEndFailsTheFinishedLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in LateRestartingSequence(base: source) }
        #expect(failed[.finishedStaysFinished]?.contains("on call 3 after it had finished") == true, "\(failed)")
    }

    @Test func rethrowingAfterTheEndFailsTheFinishedLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in RethrowingSequence(base: source) }
        #expect(failed[.finishedStaysFinished]?.contains("threw") == true, "\(failed)")
    }

    /// A deadlock, with nothing asleep, is a hang too, not only a passed horizon.
    @Test func aDeadlockIsReportedAsAHang() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            WaitsForeverAfterEndSequence(base: source)
        }
        #expect(failed[.finishedStaysFinished]?.contains("hang: virtual-time deadlock") == true, "\(failed)")
    }

    /// Counterexamples shrink by removing elements, so a fault that any
    /// one-element sample shows is reported on one element.
    @Test func counterexamplesShrinkToOneElement() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in RestartingSequence(base: source) }
        let counterexample = try #require(failed[.finishedStaysFinished])
        #expect(counterexample.hasPrefix("source = [") && !counterexample.contains(","), "\(counterexample)")
    }

    @Test func lawClockSleepsOnTheLawsVirtualTime() async throws {
        let slept = try await runInVirtualTime(horizon: .seconds(1)) { clock in
            let lawClock = LawClock(clock)
            let before = lawClock.now
            try await lawClock.sleep(for: .milliseconds(30))
            return before.duration(to: lawClock.now)
        }
        #expect(slept == .milliseconds(30))
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        #expect(
            LawIdentifier.asyncLifetime(.finishedStaysFinished).qualifiedName
                == "AsyncLifetime.finishedStaysFinished"
        )
    }
}
