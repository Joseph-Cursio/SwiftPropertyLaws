import PropertyLawAsync

/// Correct: races each upstream `next()` against an idle timeout on the law's
/// clock and finishes when the timeout wins. With the laws' gaps (25 ms at
/// most) and a 100 ms timeout, it wins only during a failing source's tail, so
/// the operator stops reading before the source throws and owes no failure.
struct IdleTimeoutSequence: AsyncSequence, Sendable {
    typealias Element = Int
    typealias Upstream = LifetimeProbeSource<Int>.AsyncIterator

    struct AsyncIterator: AsyncIteratorProtocol {
        var upstream: Upstream?
        let clock: LawClock
        let timeout: Duration

        mutating func next() async throws -> Int? {
            guard let current = upstream else { return nil }
            let lawClock = clock
            let idle = timeout
            do {
                let outcome = try await withThrowingTaskGroup(
                    of: (Int?, Upstream)?.self,
                    returning: (Int?, Upstream)?.self
                ) { group in
                    group.addTask {
                        var advanced = current
                        let element = try await advanced.next()
                        return (element, advanced)
                    }
                    group.addTask {
                        try await lawClock.sleep(for: idle)
                        return nil
                    }
                    defer { group.cancelAll() }
                    guard let first = try await group.next() else { return nil }
                    return first
                }
                guard let (element, advanced) = outcome else {
                    upstream = nil
                    return nil
                }
                upstream = element == nil ? nil : advanced
                return element
            } catch {
                upstream = nil
                throw error
            }
        }
    }

    let base: LifetimeProbeSource<Int>
    let clock: LawClock
    let timeout: Duration

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(upstream: base.makeAsyncIterator(), clock: clock, timeout: timeout)
    }
}
