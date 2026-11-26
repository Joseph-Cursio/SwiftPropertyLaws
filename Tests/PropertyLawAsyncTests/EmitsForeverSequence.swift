import Foundation

/// Faulty: swallows the upstream's ending and emits `0` forever.
struct EmitsForeverSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element == Int {
    typealias Element = Int

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var hasEnded = false

        mutating func next() async throws -> Int? {
            guard !hasEnded else { return 0 }
            do {
                if let element = try await iterator.next() { return element }
            } catch {
                // Swallowed, like the ending below.
            }
            hasEnded = true
            return 0
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
