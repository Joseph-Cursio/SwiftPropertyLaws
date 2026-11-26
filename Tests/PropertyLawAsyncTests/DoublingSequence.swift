import Foundation

/// Correct: emits every element twice, so it emits more than it receives.
struct DoublingSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var pending: Element?

        mutating func next() async throws -> Element? {
            if let element = pending {
                pending = nil
                return element
            }
            pending = try await base.next()
            return pending
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base.makeAsyncIterator(), pending: nil)
    }
}
