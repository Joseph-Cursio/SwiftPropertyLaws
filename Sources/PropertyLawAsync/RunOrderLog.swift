import Foundation

/// Test seam: the order each run started in this task's scope was given, so a
/// test can check that a law passes its trial's schedule on. The laws' own
/// outcomes cannot show it for an operator that behaves the same in every
/// order.
final class RunOrderLog: @unchecked Sendable {
    @TaskLocal static var current: RunOrderLog?

    private let lock = NSLock()
    private var recorded: [JobOrder] = []

    var orders: [JobOrder] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ order: JobOrder) {
        lock.lock()
        recorded.append(order)
        lock.unlock()
    }
}
