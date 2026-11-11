import PropertyBased

/// Outcome of a per-trial property run.
///
/// `Input` is the sampled input type — usually a tuple `(T, T)` or `(T, T, T)`
/// for laws that compare multiple values per trial. The kit's per-law helper
/// formats the counterexample from the failing input rather than asking the
/// backend to compose the message.
public enum BackendCheckResult<Input: Sendable>: Sendable {
    case passed(trialsRun: Int, initialSeed: Seed)
    case failed(trialsRun: Int, initialSeed: Seed, failingInput: Input, thrownError: ErrorBox?)
}

/// Sendable wrapper around an error's `String` description. Swift's `Error`
/// does not require `Sendable`, so we capture the message at the throw site
/// rather than smuggling the live error across an actor boundary.
public struct ErrorBox: Sendable, Hashable {
    public let message: String

    public init(_ error: Error) {
        self.message = "\(error)"
    }

    public init(message: String) {
        self.message = message
    }
}

/// Pluggable trial-loop driver for per-trial protocol laws (PRD §4.5).
///
/// v1 ships a single backend (`SwiftPropertyBasedBackend`) — the abstraction
/// stays public because the M4 dep survey established the closure-level
/// seam (`sample: (inout Xoshiro) -> Input`, `property: @Sendable (Input)
/// async throws -> Bool`) is non-leaky against any reasonable property-based
/// backend's generator/shrinking representation. A future second backend
/// can drop in without protocol changes, but v1 doesn't chase parity for
/// its own sake.
///
/// Aggregate-mode laws (Hashable.distribution etc.) bypass the backend — the
/// trial loop for "consume the entire budget in one shot" lives in the
/// kit's `AggregateDriver` and is backend-agnostic by construction.
public protocol PropertyBackend: Sendable {
    /// Stable identifier for `Environment.backendIdentity`. Recorded on every
    /// `CheckResult` so a stored seed knows which backend produced it
    /// (PRD §4.6 environment fingerprint).
    var identifier: String { get }

    /// Run `property` on independently-sampled `Input`s for up to `trials`
    /// iterations. On the first false return or first thrown error,
    /// short-circuit and report the failing input.
    ///
    /// `seed: nil` means "draw a fresh seed and report it back" — the returned
    /// `initialSeed` is always replayable.
    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        sample: @Sendable (inout Xoshiro) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input>
}
