import PropertyBased
import PropertyLawKit
import Testing
@testable import PropertyLawAsync

struct TimedAsyncLawsTests {

    @Test func intArraysPassAllTimedAsyncLaws() async throws {
        let results = try await checkTimedAsyncSequencePropertyLaws(
            for: [Int].self,
            using: Gen<Int>.int(in: -100 ... 100).array(of: 0 ... 8),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = results.map(\.protocolLaw)
        for law in TimedAsyncLaw.allCases {
            #expect(
                names.contains("TimedAsyncSequence.\(law.rawValue)"),
                "missing law \(law.rawValue)"
            )
        }
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    /// A concrete coalescing witness, so the debounce laws can't drift into
    /// vacuity: with all gaps below the interval, only the final element
    /// survives.
    @Test func debounceCoalescesRapidEventsWitness() async throws {
        let output = try await runInVirtualTime { clock in
            let source = TimedSource(
                clock: clock,
                gaps: [.milliseconds(1), .milliseconds(1), .milliseconds(1)],
                elements: [1, 2, 3]
            )
            return try await collect(source.debounce(for: .milliseconds(10), clock: clock))
        }
        #expect(output == [3])
    }

    /// The cancellation law's promptness check is what replaced "a hang is the
    /// failure", so it needs a violator of its own: a clock whose sleep cannot
    /// be cancelled. The consumer is woken at each deadline regardless, sees
    /// the whole source — a prefix, so the prefix half of the law is satisfied
    /// — and finishes long after the cancel. Only the instant gives it away.
    @Test func cancellationLawRejectsASleepThatIgnoresCancellation() async throws {
        let sample = [4, 8, 15, 16, 23, 42]
        #expect(try await cancellationCeasesEmission(of: sample) { $0 })
        #expect(try await cancellationCeasesEmission(of: sample) { CancellationDeafClock(base: $0) } == false)
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.timedAsync(.debounceIsDeterministicUnderTestClock)
        #expect(
            identifier.qualifiedName
                == "TimedAsyncSequence.debounceIsDeterministicUnderTestClock"
        )
    }
}

/// A `VirtualClock` whose sleeps run in a task of their own, which the
/// sleeper's cancellation does not reach.
private struct CancellationDeafClock: Clock {
    let base: VirtualClock

    var now: VirtualClock.Instant { base.now }

    var minimumResolution: Duration { base.minimumResolution }

    func sleep(until deadline: VirtualClock.Instant, tolerance: Duration? = nil) async throws {
        try await Task { [base] in try await base.sleep(until: deadline, tolerance: tolerance) }.value
    }
}
