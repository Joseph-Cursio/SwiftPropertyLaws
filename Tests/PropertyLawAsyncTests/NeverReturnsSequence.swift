import Foundation

/// Faulty: every `next()` waits on a continuation that nothing resumes and
/// ignores cancellation, so a consumer cancelled inside it never returns, not
/// even when the run is torn down. No clock sleeper is left, so the run ends
/// in a deadlock.
struct NeverReturnsSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable {
    typealias Element = Base.Element

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator

        mutating func next() async throws -> Element? {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                keptAlive.keep(continuation)
            }
            return nil
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator())
    }
}
