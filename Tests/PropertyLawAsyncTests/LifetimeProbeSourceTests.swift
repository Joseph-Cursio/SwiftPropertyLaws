@testable import PropertyLawAsync
import Testing

/// The probe source on its own: what it yields, how it ends, and what it records.
struct LifetimeProbeSourceTests {
    @Test func yieldsItsElementsThenFails() async throws {
        let probe = LifetimeProbe()
        let outcome = try await runInVirtualTime { clock in
            let source = LifetimeProbeSource(
                clock: clock, gaps: [.milliseconds(1), .milliseconds(2)], elements: [7, 8],
                ending: .fail, tailGap: .milliseconds(5), probe: probe
            )
            var iterator = source.makeAsyncIterator()
            var seen: [Int] = []
            do {
                while let element = try await iterator.next() { seen.append(element) }
                return (seen, false, clock.now)
            } catch is LifetimeProbeFailure {
                let after = try await iterator.next()
                return (seen, after == nil, clock.now)
            }
        }
        #expect(outcome.0 == [7, 8])
        #expect(outcome.1, "next() after the failure did not return nil")
        #expect(outcome.2 == VirtualClock.Instant(offset: .milliseconds(8)))
        #expect(probe.snapshot.made == 1)
        #expect(probe.snapshot.released == 1)
        #expect(probe.snapshot.failed)
    }

    @Test func aParkedSourceEndsWhenCancelled() async throws {
        let probe = LifetimeProbe()
        let ended = try await runInVirtualTime(horizon: .seconds(1)) { clock in
            let source = LifetimeProbeSource(
                clock: clock, gaps: [], elements: [Int](), ending: .park, tailGap: .zero, probe: probe
            )
            let consumer = Task {
                var iterator = source.makeAsyncIterator()
                return try await iterator.next() == nil
            }
            await clock.settle()
            consumer.cancel()
            return try await consumer.value
        }
        #expect(ended)
        #expect(probe.snapshot.released == probe.snapshot.made)
        #expect(probe.snapshot.failed == false)
    }

    /// A sleep cancelled between elements throws once, and the source then
    /// stays finished, as its documentation says.
    @Test func aSourceCancelledInAGapThrowsOnceThenReturnsNil() async throws {
        let outcome = try await runInVirtualTime(horizon: .seconds(5)) { clock in
            let source = LifetimeProbeSource(
                clock: clock, gaps: [.seconds(1), .seconds(1)], elements: [1, 2],
                ending: .finish, tailGap: .zero, probe: LifetimeProbe()
            )
            let consumer = Task { () -> (threw: Bool, after: Int?) in
                var iterator = source.makeAsyncIterator()
                let threw: Bool
                do {
                    _ = try await iterator.next()
                    threw = false
                } catch {
                    threw = error is CancellationError
                }
                return (threw, try await iterator.next())
            }
            await clock.settle()
            consumer.cancel()
            return try await consumer.value
        }
        #expect(outcome.threw, "the cancelled gap sleep did not throw CancellationError")
        #expect(outcome.after == nil, "the source went on after a cancelled gap")
    }
}
