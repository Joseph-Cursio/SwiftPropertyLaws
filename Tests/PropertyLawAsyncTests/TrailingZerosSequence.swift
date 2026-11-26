/// Correct and finite: forwards its base's elements, then emits `count` zeros,
/// then forwards the base's ending. For `count` near the laws' emission cap.
struct TrailingZerosSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element == Int {
    typealias Element = Int

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        var zerosLeft: Int
        /// Set once the base has ended: `nil` inside for a finish, else the failure.
        var ending: Result<Void, Error>?
        var isDone = false

        mutating func next() async throws -> Int? {
            guard !isDone else { return nil }
            if ending == nil {
                do {
                    if let element = try await iterator.next() { return element }
                    ending = .success(())
                } catch {
                    ending = .failure(error)
                }
            }
            if zerosLeft > 0 {
                zerosLeft -= 1
                return 0
            }
            isDone = true
            try ending?.get()
            return nil
        }
    }

    let base: Base
    let count: Int

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: base.makeAsyncIterator(), zerosLeft: count)
    }
}
