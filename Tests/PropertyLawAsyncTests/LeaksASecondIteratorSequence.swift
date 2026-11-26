import Foundation

/// Faulty: makes a second upstream iterator and never releases it.
struct LeaksASecondIteratorSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator

        mutating func next() async throws -> Element? {
            try await iterator.next()
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        keptAlive.keep(base.makeAsyncIterator())
        return AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
