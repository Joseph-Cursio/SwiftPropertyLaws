import Clocks
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
        let clock = TestClock()
        let source = TimedSource(
            clock: clock,
            gaps: [.milliseconds(1), .milliseconds(1), .milliseconds(1)],
            elements: [1, 2, 3]
        )
        let consumer = Task {
            try await collect(source.debounce(for: .milliseconds(10), clock: clock))
        }
        await clock.advance(by: .milliseconds(50))
        let output = try await consumer.value
        #expect(output == [3])
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.timedAsync(.debounceIsDeterministicUnderTestClock)
        #expect(
            identifier.qualifiedName
                == "TimedAsyncSequence.debounceIsDeterministicUnderTestClock"
        )
    }
}
