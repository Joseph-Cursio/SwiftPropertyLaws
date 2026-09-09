import Foundation
import PropertyBased

/// One random draw from a bounded space, with the index it came from.
///
/// Internal to the law builders: the index is what makes shrinking and coverage
/// possible, and it is deliberately stripped before a law's property closure
/// sees anything, so laws stay written against bare values.
struct IndexedDraw<Value: Sendable>: Sendable {
    let index: Int
    let value: Value
}

/// Distinct **combinations** drawn, so a sampled run can report a real
/// denominator.
///
/// **Deduplicated on purpose.** Counting draws rather than distinct cases would
/// let 1 000 draws over a 64-case space report `casesRun: 1000, spaceSize: 64`,
/// and `SpaceCoverage.isComplete` — `casesRun >= spaceSize` — would then answer
/// `true` for a run that may have missed cases entirely.
///
/// **A combination, not a position.** A binary law's input is a *pair* and a
/// ternary law's is a *triple*, so the space it samples is the product, not the
/// carrier. Recording positions separately would let a ternary law that drew all
/// 32 carrier values report complete coverage while having seen a few hundred of
/// 32 768 triples — the same overclaim in a subtler costume, and the reason this
/// records the whole tuple of indices per trial.
///
/// Shrink probes are not recorded. Coverage means the cases the law was
/// *sampled* at, not every case the minimiser evaluated on the way down.
final class DrawnCombinations: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = Set<[Int]>()

    func record(_ indices: [Int]) {
        lock.lock()
        seen.insert(indices)
        lock.unlock()
    }

    var distinctCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return seen.count
    }
}

/// Candidate indices closer to zero, biggest jump first.
///
/// A greedy descent takes the first candidate that still fails and restarts, so
/// leading with the midpoint turns the walk into a binary search rather than a
/// decrement. Because a space is ordered smallest-first, moving the index toward
/// zero moves the *case* toward the smallest one.
func indexShrinkCandidates(_ index: Int) -> [Int] {
    var candidates: [Int] = []
    var step = index / 2
    while step > 0 {
        candidates.append(index - step)
        step /= 2
    }
    if index > 0 { candidates.append(index - 1) }
    return candidates
}

/// The pieces a builder needs to sample a space while keeping the index.
struct SpaceSampler<Value: Sendable>: Sendable {
    let space: Enumeration<Value>
    let drawn = DrawnCombinations()

    init(_ space: Enumeration<Value>) {
        precondition(space.count > 0, "InputSource.sampledFromSpace: cannot draw from an empty space")
        self.space = space
    }

    /// Draw one case. Recording is deliberately *not* done here — a law's input
    /// is the whole tuple, so the combination is recorded once per trial by
    /// ``record(_:)`` after every position is drawn.
    func draw(_ rng: inout Xoshiro) -> IndexedDraw<Value> {
        let index = Gen<Int>.int(in: 0 ..< space.count).run(using: &rng)
        return IndexedDraw(index: index, value: space[index])
    }

    /// Record one trial's input, whatever its arity.
    func record(_ draws: [IndexedDraw<Value>]) {
        drawn.record(draws.map(\.index))
    }

    func shrink(_ draw: IndexedDraw<Value>) -> [IndexedDraw<Value>] {
        indexShrinkCandidates(draw.index).map { IndexedDraw(index: $0, value: space[$0]) }
    }

    /// The addresses make the case reproducible without a seed; the law's own
    /// formatter says why it failed. Multi-value laws name every position, in
    /// the order the law takes them.
    func describe(_ draws: [IndexedDraw<Value>], _ lawText: String) -> String {
        let addresses = draws.map { space.address(of: $0.index) }.joined(separator: " / ")
        return "\(addresses) — \(lawText)"
    }

    /// The denominator for a law of the given arity: `fullCount ^ arity`, since
    /// the law's input space is the product of the carrier with itself.
    ///
    /// Returns `nil` when that product overflows `Int` — a space large enough to
    /// do that has no denominator worth printing, and reporting `nil` says "this
    /// run does not know its input space", which is true and is the discipline
    /// `SpaceCoverage` already uses.
    func coverage(arity: Int) -> SpaceCoverage? {
        var size = 1
        for _ in 0 ..< arity {
            let scaled = size.multipliedReportingOverflow(by: space.fullCount)
            if scaled.overflow { return nil }
            size = scaled.partialValue
        }
        return SpaceCoverage(casesRun: drawn.distinctCount, spaceSize: size)
    }
}

extension CheckResult {
    /// Attach a coverage denominator to a result the driver produced without
    /// one. A `nil` denominator leaves the result saying it does not know its
    /// input space, which is the honest answer for a space too large to count.
    func reporting(_ coverage: SpaceCoverage?) -> CheckResult {
        guard let coverage else { return self }
        var copy = self
        copy.coverage = coverage
        return copy
    }
}
