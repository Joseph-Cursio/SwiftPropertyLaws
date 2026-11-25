import Foundation

/// Faulty: after its base ends it returns `nil` twice, then starts over.
struct LateRestartingSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        let base: Base
        var current: Base.AsyncIterator
        var nilsSinceEnd: Int?

        mutating func next() async throws -> Element? {
            if let returned = nilsSinceEnd {
                guard returned >= 2 else {
                    nilsSinceEnd = returned + 1
                    return nil
                }
                nilsSinceEnd = nil
                current = base.makeAsyncIterator()
            }
            do {
                if let element = try await current.next() { return element }
            } catch {
                nilsSinceEnd = 0
                throw error
            }
            nilsSinceEnd = 0
            return nil
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base, current: base.makeAsyncIterator())
    }
}
