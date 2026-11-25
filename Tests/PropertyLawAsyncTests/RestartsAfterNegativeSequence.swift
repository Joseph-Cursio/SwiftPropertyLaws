/// Faulty only for samples with a negative element: after its base ends it
/// starts over if it has seen one. Shrinking has to keep that element, so the
/// reported counterexample is the one negative element.
struct RestartsAfterNegativeSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable
where Base.Element == Int {
    typealias Element = Int

    struct AsyncIterator: AsyncIteratorProtocol {
        let base: Base
        var current: Base.AsyncIterator
        var sawNegative = false
        var isDone = false

        mutating func next() async throws -> Int? {
            guard !isDone else { return nil }
            do {
                if let element = try await current.next() {
                    if element < 0 { sawNegative = true }
                    return element
                }
            } catch {
                endOrRestart()
                throw error
            }
            endOrRestart()
            return nil
        }

        private mutating func endOrRestart() {
            if sawNegative {
                current = base.makeAsyncIterator()
            } else {
                isDone = true
            }
        }
    }

    let base: Base

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: base, current: base.makeAsyncIterator())
    }
}
