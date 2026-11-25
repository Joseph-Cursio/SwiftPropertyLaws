/// Faulty: starts its base over after a clean finish, but stays done after a
/// failure, so only the finishing half of `finishedStaysFinished` catches it.
struct RestartsOnlyAfterFinishSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        let base: Base
        var current: Base.AsyncIterator
        var hasFailed = false

        mutating func next() async throws -> Element? {
            guard !hasFailed else { return nil }
            do {
                if let element = try await current.next() { return element }
            } catch {
                hasFailed = true
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
