import Foundation

/// Sendable counter for per-trial coverage classifications. Per-law check
/// closures wrap their property to call `record(...)` after running their
/// classifier; the kit reads `snapshot()` once the backend returns and
/// packages it into `CheckResult.coverageHints`.
internal final class CoverageAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var inputClasses: [String: Int] = [:]
    private var boundaryHits: [String: Int] = [:]

    func record(classes: Set<String>, boundaries: Set<String>) {
        lock.lock()
        for label in classes { inputClasses[label, default: 0] += 1 }
        for label in boundaries { boundaryHits[label, default: 0] += 1 }
        lock.unlock()
    }

    func snapshot() -> CoverageHints {
        lock.lock()
        let classesCopy = inputClasses
        let boundariesCopy = boundaryHits
        lock.unlock()
        return CoverageHints(inputClasses: classesCopy, boundaryHits: boundariesCopy)
    }
}
