import Foundation

/// Upstream iterators and continuations the leaking planted operators keep
/// alive on purpose, so a leak outlives the trial.
final class KeptAlive: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Any] = []

    func keep(_ item: Any) {
        lock.lock()
        items.append(item)
        lock.unlock()
    }
}

let keptAlive = KeptAlive()
