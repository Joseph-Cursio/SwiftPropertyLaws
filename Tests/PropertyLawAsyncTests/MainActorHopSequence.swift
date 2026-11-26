/// Faulty for the lifetime laws: each `next()` hops through `MainActor`
/// before forwarding, which takes the operator's work out of virtual time.
struct MainActorHopSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator

        mutating func next() async throws -> Element? {
            await MainActor.run {}
            return try await iterator.next()
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
