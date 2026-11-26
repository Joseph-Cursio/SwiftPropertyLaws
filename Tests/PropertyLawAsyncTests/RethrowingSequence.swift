import Foundation

/// Faulty: rethrows the upstream failure on every later call.
struct RethrowingSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var failure: Error?

        mutating func next() async throws -> Element? {
            if let failure { throw failure }
            do {
                return try await iterator.next()
            } catch {
                failure = error
                throw error
            }
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
