import Foundation

/// Faulty: after its base ends, the next call waits on a continuation that
/// nothing resumes, with no sleeper left: a deadlock, not a passed horizon.
struct WaitsForeverAfterEndSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var hasEnded = false

        mutating func next() async throws -> Element? {
            if hasEnded {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    keptAlive.keep(continuation)
                }
                return nil
            }
            do {
                if let element = try await iterator.next() { return element }
            } catch {
                hasEnded = true
                throw error
            }
            hasEnded = true
            return nil
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
