import Foundation

/// Sendable accumulator for per-trial near-miss observations (PRD §4.6).
///
/// Per-law check closures capture an instance, write to it during their
/// trial loop, and the kit's `PerLawDriver` / `AggregateDriver` reads
/// `snapshot()` once the backend returns. The kit packages the snapshot
/// into `CheckResult.nearMisses`, preserving the §4.6 contract that
/// `nil` means "this law/backend doesn't track near-misses" while `[]`
/// means "tracked but found none".
///
/// Backed by `NSLock` rather than Swift 6's `Mutex` because the package
/// supports macOS 14 and `Mutex` requires macOS 15 / Synchronization. The
/// sync work under lock is constant-time (one append, or one array copy).
internal final class NearMissCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock()
        entries.append(entry)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        let copy = entries
        lock.unlock()
        return copy
    }
}
