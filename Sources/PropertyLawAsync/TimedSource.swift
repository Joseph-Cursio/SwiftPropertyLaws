/// A finite async sequence that yields each element after a virtual-time
/// gap on the injected clock. The gaps are the *entire* time behavior —
/// nothing here touches a wall clock.
struct TimedSource<Element: Sendable, ClockType: Clock & Sendable>: AsyncSequence, Sendable
where ClockType.Duration == Swift.Duration {
    let clock: ClockType
    let gaps: [Swift.Duration]
    let elements: [Element]

    struct AsyncIterator: AsyncIteratorProtocol {
        let clock: ClockType
        let gaps: [Swift.Duration]
        let elements: [Element]
        var position = 0

        mutating func next() async throws -> Element? {
            guard position < elements.count else { return nil }
            try await clock.sleep(for: gaps[position], tolerance: nil)
            defer { position += 1 }
            return elements[position]
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(clock: clock, gaps: gaps, elements: elements)
    }
}
