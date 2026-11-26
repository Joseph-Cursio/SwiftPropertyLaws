import Foundation

/// A continuation parked by one task and resumed later by another, from any
/// thread. `stored` is set once the continuation is in the slot.
final class ContinuationSlot: @unchecked Sendable {
    let stored = Latch()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    /// Park the calling task here until ``resume()``.
    func park() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            stored.set()
        }
    }

    /// Resume the parked task, if one is parked.
    func resume() {
        lock.lock()
        let parked = continuation
        continuation = nil
        lock.unlock()
        parked?.resume()
    }
}
