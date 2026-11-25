import Foundation

/// Faulty: replaces the upstream failure with ``PlantedOtherFailure``, or, with
/// `immediately`, throws it on the first call.
struct ReplacesFailureSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        let immediately: Bool
        var isDone = false

        mutating func next() async throws -> Element? {
            guard !isDone else { return nil }
            if immediately {
                isDone = true
                throw PlantedOtherFailure()
            }
            do {
                return try await iterator.next()
            } catch {
                isDone = true
                throw PlantedOtherFailure()
            }
        }
    }

    let base: Base
    let immediately: Bool

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator(), immediately: immediately)
    }
}
