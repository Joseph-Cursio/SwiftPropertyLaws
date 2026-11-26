/// A planted operator that breaks only `finishedStaysFinished`: when its base
/// ends, it starts the base over, so a finished iterator emits again.
struct RestartingSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        let base: Base
        var current: Base.AsyncIterator

        mutating func next() async throws -> Element? {
            do {
                if let element = try await current.next() { return element }
            } catch {
                current = base.makeAsyncIterator()
                throw error
            }
            current = base.makeAsyncIterator()
            return nil
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base, current: base.makeAsyncIterator())
    }
}
