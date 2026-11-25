/// Faulty: turns the upstream failure into a `CancellationError`.
struct ReplacesFailureWithCancellationSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var isDone = false

        mutating func next() async throws -> Element? {
            guard !isDone else { return nil }
            do {
                return try await iterator.next()
            } catch {
                isDone = true
                throw CancellationError()
            }
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
