/// The clock a lifetime law hands the operator under test.
///
/// It runs on the law's own virtual time: `now` moves only when every task in
/// the run is blocked, so an operator that sleeps on it, like
/// `debounce(for:clock:)`, behaves the same on every run and costs no wall
/// time. It has no public initializer; ``checkAsyncLifetimePropertyLaws(for:using:applying:)``
/// makes one per trial, and it is only meaningful inside that trial.
public struct LawClock: Clock {
    /// A point on the law's virtual timeline.
    public struct Instant: InstantProtocol {
        let base: VirtualClock.Instant

        public func advanced(by duration: Duration) -> Self {
            Self(base: base.advanced(by: duration))
        }

        public func duration(to other: Self) -> Duration {
            base.duration(to: other.base)
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.base < rhs.base
        }
    }

    let base: VirtualClock

    public var now: Instant { Instant(base: base.now) }

    public var minimumResolution: Duration { .zero }

    init(_ base: VirtualClock) {
        self.base = base
    }

    /// Suspends until the law's virtual time reaches `deadline`. Cancellation
    /// wakes the sleeper with `CancellationError` without moving time.
    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        try await base.sleep(until: deadline.base, tolerance: tolerance)
    }
}
