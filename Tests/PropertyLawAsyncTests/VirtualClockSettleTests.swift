import Foundation
@testable import PropertyLawAsync
import Testing

/// `settle()` returns once every other task is blocked, before time moves.
struct VirtualClockSettleTests {
    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [String] = []

        var entries: [String] {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }

        func append(_ entry: String) {
            lock.lock()
            stored.append(entry)
            lock.unlock()
        }
    }

    @Test func settleWaitsForOtherWorkButNotForSleepers() async throws {
        let log = Log()
        let settledAt = try await runInVirtualTime(horizon: .seconds(10)) { clock in
            let other = Task {
                await Task.yield()
                log.append("other ran")
                try? await clock.sleep(for: .seconds(5))
                log.append("other woke")
            }
            await clock.settle()
            log.append("settled")
            let settledAt = clock.now
            other.cancel()
            await other.value
            return settledAt
        }
        #expect(settledAt == VirtualClock.Instant(offset: .zero), "settle() moved time")
        #expect(log.entries == ["other ran", "settled", "other woke"])
    }

    /// Teardown resumes settlers too: a task woken by teardown that then
    /// settles is not left parked.
    @Test func teardownResumesATaskThatSettlesWhileBeingTornDown() async throws {
        let log = Log()
        _ = try await runInVirtualTime(horizon: .seconds(10)) { clock in
            Task {
                try? await clock.sleep(for: .seconds(5))
                await clock.settle()
                log.append("settled during teardown")
            }
            return 0
        }
        #expect(log.entries == ["settled during teardown"])
    }
}
