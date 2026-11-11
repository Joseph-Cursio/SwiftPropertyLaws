import PropertyBased

/// Sequence whose `underestimatedCount` lies high — claims more elements than
/// the iterator can produce. Violates Sequence.underestimatedCountLowerBound.
struct LyingUnderestimatedCount: Sequence, Sendable, CustomStringConvertible {
    let payload: [Int]
    let claimed: Int

    var underestimatedCount: Int { claimed }

    func makeIterator() -> IndexingIterator<[Int]> { payload.makeIterator() }

    var description: String { "Lying(payload=\(payload), claimed=\(claimed))" }
}

/// Sequence backed by a shared, mutable counter so two iterators perturb each
/// other. Violates Sequence.multiPassConsistency and makeIteratorIndependence.
final class SharedCounterBox: @unchecked Sendable {
    var value: Int = 0
}

struct SharedCounterSequence: Sequence, Sendable, CustomStringConvertible {
    let cap: Int
    let box: SharedCounterBox

    func makeIterator() -> Iterator { Iterator(cap: cap, box: box) }

    struct Iterator: IteratorProtocol {
        let cap: Int
        let box: SharedCounterBox

        mutating func next() -> Int? {
            // Each call advances the SHARED counter, so two iterators race
            // through the same global state.
            guard box.value < cap else { return nil }
            let element = box.value
            box.value += 1
            return element
        }
    }

    var description: String { "SharedCounter(cap=\(cap))" }
}

extension Gen where Value == LyingUnderestimatedCount {
    static func lyingUnderestimated() -> Generator<LyingUnderestimatedCount, some SendableSequenceType> {
        // Claim 5 elements but only ever supply 0–2 — guaranteed lie.
        Gen<Int>.int(in: 0...10)
            .array(of: 0...2)
            .map { LyingUnderestimatedCount(payload: $0, claimed: 5) }
    }
}

extension Gen where Value == SharedCounterSequence {
    static func sharedCounter() -> Generator<SharedCounterSequence, some SendableSequenceType> {
        Gen<Int>.int(in: 3...6)
            .map { cap in SharedCounterSequence(cap: cap, box: SharedCounterBox()) }
    }
}
