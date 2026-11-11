import PropertyBased

/// Sequence whose iterator yields elements forever — violates
/// single-pass-yield. `underestimatedCount` is small so the iterationCap is
/// small enough to trigger within the test budget.
struct InfiniteCounterSequence: Sequence, Sendable, CustomStringConvertible {
    let underestimated: Int

    var underestimatedCount: Int { underestimated }

    func makeIterator() -> Iterator { Iterator() }

    struct Iterator: IteratorProtocol {
        var counter: Int = 0

        mutating func next() -> Int? {
            counter += 1
            return counter
        }
    }

    var description: String { "Inf(uec=\(underestimated))" }
}

/// Sequence whose iterator yields a fixed number of elements, then `nil`, then
/// resumes yielding the same elements again — violates IteratorProtocol's
/// termination-stability law.
struct ResumingAfterNilSequence: Sequence, Sendable, CustomStringConvertible {
    let payload: [Int]

    func makeIterator() -> Iterator { Iterator(payload: payload) }

    struct Iterator: IteratorProtocol {
        let payload: [Int]
        var phase: Int = 0
        var index: Int = 0

        mutating func next() -> Int? {
            // phase 0: yield payload, then return nil.
            // phase 1: yield payload again — termination-stability violation.
            switch phase {
            case 0:
                if index < payload.count {
                    let element = payload[index]
                    index += 1
                    return element
                }
                phase = 1
                index = 0
                return nil

            case 1:
                if index < payload.count {
                    let element = payload[index]
                    index += 1
                    return element
                }
                return nil

            default:
                return nil
            }
        }
    }

    var description: String { "Resuming(\(payload))" }
}

extension Gen where Value == ResumingAfterNilSequence {
    static func resumingAfterNil() -> Generator<ResumingAfterNilSequence, some SendableSequenceType> {
        Gen<Int>.int(in: 0...10)
            .array(of: 1...4)
            .map { ResumingAfterNilSequence(payload: $0) }
    }
}

extension Gen where Value == InfiniteCounterSequence {
    static func infiniteCounter() -> Generator<InfiniteCounterSequence, some SendableSequenceType> {
        Gen<Int>.int(in: 0...5)
            .map { InfiniteCounterSequence(underestimated: $0) }
    }
}
