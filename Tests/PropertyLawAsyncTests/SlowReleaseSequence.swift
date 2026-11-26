import Foundation

/// Correct, but releases its upstream iterator a few scheduler hops after
/// the drop, as an operator that keeps its upstream in a task does. The
/// laws' `settle()` is what waits for it.
struct SlowReleaseSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable {
    typealias Element = Base.Element

    final class Holder: @unchecked Sendable {
        var iterator: Base.AsyncIterator?

        init(_ iterator: Base.AsyncIterator) {
            self.iterator = iterator
        }
    }

    final class Handle: Sendable {
        let holder: Holder

        init(_ holder: Holder) {
            self.holder = holder
        }

        deinit {
            let releasing = holder
            Task {
                for _ in 0 ..< 4 {
                    await Task.yield()
                }
                releasing.iterator = nil
            }
        }
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let handle: Handle

        mutating func next() async throws -> Element? {
            guard var iterator = handle.holder.iterator else { return nil }
            handle.holder.iterator = nil
            defer { handle.holder.iterator = iterator }
            return try await iterator.next()
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(handle: Handle(Holder(base.makeAsyncIterator())))
    }
}
