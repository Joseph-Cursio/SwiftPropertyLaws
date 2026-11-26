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
/// window. The trip back can take longer than the window: under heavy load
/// (measured at a load average of 160: p99 40 ms, worst 98 ms), and for
/// seconds when other tests in the process hold every pool thread (see
/// ``patience``). The run then reports a deadlock. An escape's kind does not
/// depend on timing, so a deadlock is run again until ``patience`` runs out.
func escapingVerdict<Value: Sendable>(
    _ body: @escaping @Sendable (VirtualClock) async throws -> Value
) async throws -> Result<Value, VirtualTimeError> {
    let giveUp = ContinuousClock.now.advanced(by: patience)
    var ended = try await verdict(body)
    while case .failure(.deadlock) = ended, ContinuousClock.now < giveUp {
        ended = try await verdict(body)
    }
    return ended
}
