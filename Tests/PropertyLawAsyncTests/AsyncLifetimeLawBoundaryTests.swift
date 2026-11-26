import PropertyBased
@testable import PropertyLawAsync
import PropertyLawKit
import Testing

/// The edges of what the lifetime laws promise: the per-step time allowance,
/// the emission cap, shrinking, the default overload, and the timing details
/// that let each law see the fault it is for. Each test here came from a
/// mutation-testing review, and kills a mutant of the laws that the tests in
/// ``AsyncLifetimeLawsTests`` let survive.
struct AsyncLifetimeLawBoundaryTests {
    /// An operator that needs 150 ms of the clock per element is within the
    /// laws' 200 ms per step.
    @Test func aSlowOperatorWithinTheAllowancePassesEveryLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, clock in
            ForwardingSequence(base: source, defect: .correct, delay: (clock, .milliseconds(150)))
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// The release law's deadline allows a step, so a slow operator's first
    /// element still arrives in time and its leak is still seen.
    @Test func aSlowOperatorKeepingUpstreamStillFailsTheReleaseLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, clock in
            ForwardingSequence(base: source, defect: .keepsUpstreamAfterDrop, delay: (clock, .milliseconds(150)))
        }
        #expect(Set(failed.keys) == [.releasesUpstreamWhenConsumerLeaves], "\(failed)")
    }

    /// Far past the allowance, an operator is reported as a hang.
    @Test func anOperatorFarSlowerThanTheAllowanceIsReportedAsAHang() async throws {
        let failed = try await LifetimeLawResults.failures { source, clock in
            ForwardingSequence(base: source, defect: .correct, delay: (clock, .seconds(1)))
        }
        #expect(failed[.finishedStaysFinished]?.contains("hang:") == true, "\(failed)")
    }

    /// With a delay, the dropped failure arrives after `failsAt`; the consumer's
    /// pause must still outlast it.
    @Test func aDelayedOperatorDroppingAFailureFailsOnlyTheFailureLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, clock in
            ForwardingSequence(base: source, defect: .dropsFailureWithoutDemand, delay: (clock, .milliseconds(5)))
        }
        #expect(Set(failed.keys) == [.failureReachesConsumerWithoutDemand], "\(failed)")
    }

    /// A holding operator, like `debounce`, sees the failure without demand
    /// only because the source waits out a tail gap after its last element.
    @Test func aHoldingOperatorDroppingAFailureFailsTheFailureLaw() async throws {
        let single = LifetimeLawResults.singleElementSamples
        let failed = try await LifetimeLawResults.failures(using: single) { source, clock in
            HoldsElementsSequence(base: source, clock: clock, hold: .milliseconds(10))
        }
        #expect(
            failed[.failureReachesConsumerWithoutDemand]?.contains("finished without delivering it") == true,
            "\(failed)"
        )
    }

    /// Leaking only when cancelled while waiting is the cancellation law's
    /// case; the release law, whose consumer is still waiting at its deadline,
    /// asserts nothing.
    @Test func leakingOnlyWhenCancelledWhileWaitingFailsOnlyTheCancellationLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source.filter { _ in false }, defect: .forgetsUpstreamWhenCancelledWhileWaiting)
        }
        #expect(Set(failed.keys) == [.cancellationReachesUpstream], "\(failed)")
    }

    /// A consumer cancelled at the deadline whose next() never returns is
    /// reported as the operator ignoring cancellation, not as out of scope.
    @Test func aCancelledConsumerThatNeverReturnsIsReportedAsIgnoringCancellation() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ForwardingSequence(base: source.filter { _ in false }, defect: .ignoresCancellationInNext)
        }
        #expect(failed[.cancellationReachesUpstream]?.contains("ignores cancellation") == true, "\(failed)")
        #expect(failed[.releasesUpstreamWhenConsumerLeaves]?.contains("ignores cancellation") == true, "\(failed)")
    }

    /// A source cancelled during its tail never threw, so an operator that
    /// stops reading then owes no failure.
    @Test func anOperatorThatStopsReadingOnATimerPassesEveryLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, clock in
            IdleTimeoutSequence(base: source, clock: clock, timeout: .milliseconds(100))
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    @Test func replacingTheFailureWithCancellationFailsTheFailureLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            ReplacesFailureWithCancellationSequence(base: source)
        }
        #expect(
            failed[.failureReachesConsumerWithoutDemand]?.contains("instead of the upstream failure") == true,
            "\(failed)"
        )
    }

    /// Only a finishing source catches this one, so both endings must be used.
    @Test func restartingOnlyAfterACleanFinishFailsOnlyTheFinishedLaw() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in
            RestartsOnlyAfterFinishSequence(base: source)
        }
        #expect(Set(failed.keys) == [.finishedStaysFinished], "\(failed)")
    }

    /// A finite operator that emits thousands of elements is within the cap.
    @Test func anOperatorThatEmitsThousandsButEndsPassesEveryLaw() async throws {
        let single = LifetimeLawResults.singleElementSamples
        let failed = try await LifetimeLawResults.failures(using: single) { source, _ in
            TrailingZerosSequence(base: source, count: lifetimeEmissionCap - 1_000)
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// Shrinking removes any element, not only the last: the counterexample is
    /// the one negative element the fault depends on.
    @Test func counterexamplesShrinkToTheElementThatMatters() async throws {
        let startsNonNegative = LifetimeLawResults.samples.map { sample in [abs(sample[0])] + sample.dropFirst() }
        let failed = try await LifetimeLawResults.failures(using: startsNonNegative) { source, _ in
            RestartsAfterNegativeSequence(base: source)
        }
        let counterexample = try #require(failed[.finishedStaysFinished], "\(failed)")
        #expect(counterexample.hasPrefix("source = [-") && !counterexample.contains(","), "\(counterexample)")
    }

    @Test func theDefaultOverloadUsesTheDefaultOptions() async throws {
        let samples = LifetimeLawResults.samples
        let results = try await checkAsyncLifetimePropertyLaws(for: [Int].self, using: samples) { source, _ in source }
        #expect(results.count == AsyncLifetimeLaw.allCases.count)
        #expect(results.allSatisfy { $0.trials == TrialBudget.standard.trialCount }, "\(results.map(\.trials))")
        await #expect(throws: PropertyLawViolation.self) {
            try await checkAsyncLifetimePropertyLaws(for: [Int].self, using: samples) { source, _ in
                RestartingSequence(base: source)
            }
        }
    }

    /// A finishing source waits out its tail gap too, at the unit level: no
    /// law uses a finishing tail today.
    @Test func aFinishingSourceWaitsItsTailGap() async throws {
        let endedAt = try await runInVirtualTime { clock in
            let source = LifetimeProbeSource(
                clock: clock, gaps: [.milliseconds(1)], elements: [7],
                ending: .finish, tailGap: .milliseconds(5), probe: LifetimeProbe()
            )
            var iterator = source.makeAsyncIterator()
            while try await iterator.next() != nil {
                // Drain to the end.
            }
            return clock.now
        }
        #expect(endedAt == VirtualClock.Instant(offset: .milliseconds(6)))
    }
}
