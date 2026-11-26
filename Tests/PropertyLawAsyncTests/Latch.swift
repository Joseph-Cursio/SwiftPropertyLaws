import Foundation

/// A one-way flag set from any thread, which an async test can wait for in
/// real time.
final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    /// Whether the latch is set within `limit` of real time.
    func isSet(within limit: Duration) async throws -> Bool {
        let giveUp = ContinuousClock.now.advanced(by: limit)
        while !isSet {
            guard ContinuousClock.now < giveUp else { return false }
            try await Task.sleep(for: .milliseconds(5))
        }
        return true
    }
}
