import Foundation

/// Faulty: reads the upstream failure and finishes as if nothing happened.
struct SwallowsFailureSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator

        mutating func next() async throws -> Element? {
            try? await iterator.next()
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
