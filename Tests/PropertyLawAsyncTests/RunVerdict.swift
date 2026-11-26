@testable import PropertyLawAsync

/// How a run ended: its value, or the scheduler's error.
func verdict<Value: Sendable>(
    _ body: @escaping @Sendable (VirtualClock) async throws -> Value
) async throws -> Result<Value, VirtualTimeError> {
    do {
        return .success(try await runInVirtualTime(body))
    } catch let error as VirtualTimeError {
        return .failure(error)
    }
}

/// The verdict of a run whose work escapes and comes back within the grace
/// window. Under heavy load the trip back can take longer than the window —
/// measured at a load average of 160: p99 40 ms, worst 98 ms — and the run
/// then reports a deadlock. An escape's kind does not depend on timing, so a
/// deadlock is run again, twice at most, before it counts.
func escapingVerdict<Value: Sendable>(
    _ body: @escaping @Sendable (VirtualClock) async throws -> Value
) async throws -> Result<Value, VirtualTimeError> {
    var ended = try await verdict(body)
    for _ in 0 ..< 2 {
        guard case .failure(.deadlock) = ended else { break }
        ended = try await verdict(body)
    }
    return ended
}
