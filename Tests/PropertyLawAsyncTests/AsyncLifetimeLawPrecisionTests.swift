import PropertyBased
@testable import PropertyLawAsync
import PropertyLawKit
import Testing

/// Exact behaviour the broader lifetime-law tests leave loose: the emission
/// cap's size and where it bites, the shrinker's pair removals and their
/// order, and which hangs are reported as the operator ignoring cancellation.
struct AsyncLifetimeLawPrecisionTests {
    /// One element plus cap - 1 zeros, then the ending: exactly `cap` reads
    /// after the pause in the failure law, exactly `cap` emissions in the
    /// finished law. Within the cap, so every law holds.
    @Test func emittingUpToTheCapPassesEveryLaw() async throws {
        let single = LifetimeLawResults.singleElementSamples
        let failed = try await LifetimeLawResults.failures(using: single) { source, _ in
            TrailingZerosSequence(base: source, count: lifetimeEmissionCap - 1)
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// One more zero passes the cap in both laws that read to the end.
    @Test func emittingOneMoreThanTheCapFailsTheFailureAndFinishedLaws() async throws {
        let single = LifetimeLawResults.singleElementSamples
        let failed = try await LifetimeLawResults.failures(using: single) { source, _ in
            TrailingZerosSequence(base: source, count: lifetimeEmissionCap)
        }
        #expect(failed[.failureReachesConsumerWithoutDemand]?.contains("the law's cap") == true, "\(failed)")
        #expect(failed[.finishedStaysFinished]?.contains("the law's cap") == true, "\(failed)")
    }

    /// The cap's size is part of the contract, not just its use: 9 000
    /// elements, a fixed count rather than one derived from the constant, are
    /// within it.
    @Test func nineThousandElementsAreWithinTheCap() async throws {
        let single = LifetimeLawResults.singleElementSamples
        let failed = try await LifetimeLawResults.failures(using: single) { source, _ in
            TrailingZerosSequence(base: source, count: 9_000)
        }
        #expect(failed.isEmpty, "\(failed)")
    }

    /// And 11 000, again a fixed count, are past it.
    @Test func elevenThousandElementsArePastTheCap() async throws {
        let single = LifetimeLawResults.singleElementSamples
        let failed = try await LifetimeLawResults.failures(using: single) { source, _ in
            TrailingZerosSequence(base: source, count: 11_000)
        }
        #expect(failed[.failureReachesConsumerWithoutDemand]?.contains("the law's cap") == true, "\(failed)")
        #expect(failed[.finishedStaysFinished]?.contains("the law's cap") == true, "\(failed)")
    }

    /// A fault that shows only with a finishing (even-length) source shrinks
    /// to two elements: removing one element flips the parity, removing an
    /// adjacent pair keeps it.
    @Test func aParityDependentFaultShrinksToTwoElements() async throws {
        let long = Gen<Int>.int(in: -100 ... 100).array(of: 4 ... 6)
        let failed = try await LifetimeLawResults.failures(using: long) { source, _ in
            RestartsOnlyAfterFinishSequence(base: source)
        }
        let counterexample = try #require(failed[.finishedStaysFinished], "\(failed)")
        let list = try #require(counterexample.split(separator: ";").first)
        #expect(list.filter { $0 == "," }.count == 1, "\(counterexample)")
    }

    /// Single removals come before pair removals. From [-1, -2, 5], removing
    /// the first element keeps a negative one and leads to [-2]; trying pairs
    /// first would remove -2 and 5 together and stop at [-1].
    @Test func shrinkingTriesSingleRemovalsBeforePairs() async throws {
        let failed = try await LifetimeLawResults.failures(using: Gen<[Int]>.always([-1, -2, 5])) { source, _ in
            RestartsAfterNegativeSequence(base: source)
        }
        let counterexample = try #require(failed[.finishedStaysFinished], "\(failed)")
        #expect(counterexample.hasPrefix("source = [-2];"), "\(counterexample)")
    }

    /// A consumer cancelled inside a `next()` that never returns, even once
    /// the run is torn down, is still reported as the operator ignoring
    /// cancellation: the laws mark the consumer cancelled before they wait for
    /// it, not after. The laws that never cancel report a plain hang.
    @Test func aConsumerStuckForGoodAfterCancellationIsReportedAsIgnoringIt() async throws {
        let failed = try await LifetimeLawResults.failures { source, _ in NeverReturnsSequence(base: source) }
        #expect(failed[.releasesUpstreamWhenConsumerLeaves]?.contains("ignores cancellation") == true, "\(failed)")
        #expect(failed[.cancellationReachesUpstream]?.contains("ignores cancellation") == true, "\(failed)")
        for law in [AsyncLifetimeLaw.failureReachesConsumerWithoutDemand, .finishedStaysFinished] {
            let reason = try #require(failed[law], "\(failed)")
            #expect(reason.contains("hang:") && !reason.contains("ignores cancellation"), "\(reason)")
        }
    }
}
