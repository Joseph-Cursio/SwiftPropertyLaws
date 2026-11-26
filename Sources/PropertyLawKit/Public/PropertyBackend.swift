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

/// A ``PropertyBackend`` that implements only
/// ``PropertyBackend/check(trials:seed:drawing:property:)`` (4.13.0).
///
/// Conforming to this protocol instead of `PropertyBackend` supplies the
/// default ``PropertyBackend/check(trials:seed:sample:property:)``, so code
/// that calls the `Xoshiro` form keeps working against the new engine.
///
/// Implement `drawing:`. A conforming type that implements neither
/// requirement compiles, and its first `check` call traps.
public protocol DrawingPropertyBackend: PropertyBackend {}

/// The plumbing the two default `check` implementations share.
enum BackendBridge {
    /// The backend type whose default `drawing:` is running in this task. Its
    /// default `sample:` running at the same time means the type implements
    /// neither requirement, and the two defaults would call each other forever.
    @TaskLocal static var drawingDefaultInFlight: ObjectIdentifier?

    /// The `Xoshiro` to continue from after a `drawing` closure ran on one.
    ///
    /// A closure that replaced the generator with another type leaves no
    /// `Xoshiro` to write back, so the trial loop continues from one seeded by
    /// the replacement, which keeps the run deterministic.
    static func xoshiro(after generator: inout any SeededRandomNumberGenerator) -> Xoshiro {
        if let xoshiro = generator as? Xoshiro { return xoshiro }
        return xoshiro(seededFrom: &generator)
    }

    /// A `Xoshiro` seeded from the next four words of `generator`.
    static func xoshiro(seededFrom generator: inout any SeededRandomNumberGenerator) -> Xoshiro {
        Xoshiro(seed: (generator.next(), generator.next(), generator.next(), generator.next()))
    }
}

/// Pluggable trial-loop driver for per-trial protocol laws (PRD §4.5).
///
/// v1 ships a single backend (`SwiftPropertyBasedBackend`) — the abstraction
/// stays public because the M4 dep survey established the closure-level
/// seam (a sampling closure plus `property: @Sendable (Input) async throws
/// -> Bool`) is non-leaky against any reasonable property-based backend's
/// generator/shrinking representation. A future second backend can drop in
/// without protocol changes, but v1 doesn't chase parity for its own sake.
///
/// ## Two sampling requirements (4.13.0)
///
/// The protocol carries the same trial loop twice, differing only in the
/// generator the sampling closure draws from:
///
/// - ``check(trials:seed:sample:property:)`` hands the closure an
///   `inout Xoshiro`. It is the original requirement, and every backend
///   written before 4.13.0 implements it.
/// - ``check(trials:seed:drawing:property:)`` hands it an
///   `inout any SeededRandomNumberGenerator`, so an engine can draw from a
///   generator of its own. The kit's law drivers call this one.
///
/// `PropertyBackend` supplies the default `drawing:` and
/// ``DrawingPropertyBackend`` supplies the default `sample:`, so a backend
/// implements one of them:
///
/// - **An existing backend** implements `sample:` and conforms to
///   `PropertyBackend` as before. The default `drawing:` runs the kit's
///   closures on the backend's own `Xoshiro`, writing the generator's state
///   back after every draw, so a seed replays as the same inputs.
/// - **A new engine** implements `drawing:` and conforms to
///   ``DrawingPropertyBackend``, which supplies the default `sample:`.
///
/// A type that conforms to `PropertyBackend` alone and implements neither
/// does not compile: `sample:` has no default there. A type that conforms to
/// `DrawingPropertyBackend` and implements neither compiles, because each
/// requirement then has a default, and Swift cannot require "at least one of
/// two". Calling it traps with a message naming the type. Without the trap
/// the two defaults would call each other forever, and because they are
/// `async` their frames live on the heap: measured, that grows the process
/// by gigabytes a second rather than overflowing the stack.
///
/// ## What the backend does not drive
///
/// Only laws run through the kit's per-trial driver reach the backend.
/// Aggregate-mode laws (`Hashable.distribution`,
/// `InteractionInvariant.isFalsifiable`) consume the budget in one shot in the
/// kit's `AggregateDriver`; laws over a walked space run in
/// `EnumerationDriver`; and the three equal-value laws under
/// `LawCheckOptions.equalValuePairing` run in `DrawPoolDriver`. All three
/// draw from the kit's own `Xoshiro`, whatever `LawCheckOptions.backend`
/// says, and record its identifier only in the environment fingerprint.
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
    ///
    /// The original requirement. A ``DrawingPropertyBackend`` gets a default
    /// that runs `sample` on the engine's own generator: directly when that
    /// generator is a `Xoshiro`, and otherwise on a `Xoshiro` seeded from four
    /// of its words per draw.
    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        sample: @Sendable (inout Xoshiro) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input>

    /// The same trial loop, with a sampling closure that draws from any
    /// seeded generator (4.13.0).
    ///
    /// The kit's per-trial law driver calls this requirement. `drawing` must
    /// leave the generator it is given in place: it draws from it, and the
    /// backend keeps using that same generator for the next trial.
    ///
    /// The default, for a backend that implements only
    /// ``check(trials:seed:sample:property:)``, calls that requirement and
    /// runs `drawing` on its `Xoshiro`, writing the advanced state back after
    /// each draw.
    ///
    /// Marked `@_disfavoredOverload` so that a call whose sampling closure is
    /// an unlabeled trailing closure, which matches both requirements, still
    /// resolves to `sample:` as it did before 4.13.0. Without it such a call
    /// fails to compile with "ambiguous use of 'check'". A call that labels
    /// `drawing:` is unaffected.
    @_disfavoredOverload
    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        drawing: @Sendable (inout any SeededRandomNumberGenerator) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input>
}

public extension PropertyBackend {
    /// Default for a backend that implements only the `Xoshiro` requirement.
    @_disfavoredOverload
    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        drawing: @Sendable (inout any SeededRandomNumberGenerator) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        await BackendBridge.$drawingDefaultInFlight.withValue(ObjectIdentifier(Self.self)) {
            await check(
                trials: trials,
                seed: seed,
                sample: { xoshiro in
                    // `Xoshiro` is a value type: boxing it copies its state, so the
                    // advanced copy must be written back, or the next trial would
                    // redraw the same input.
                    var generator: any SeededRandomNumberGenerator = xoshiro
                    let input = drawing(&generator)
                    xoshiro = BackendBridge.xoshiro(after: &generator)
                    return input
                },
                property: property
            )
        }
    }
}

public extension DrawingPropertyBackend {
    /// Default for a backend that implements only the `drawing:` requirement.
    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        sample: @Sendable (inout Xoshiro) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        if BackendBridge.drawingDefaultInFlight == ObjectIdentifier(Self.self) {
            preconditionFailure(
                "\(Self.self) conforms to DrawingPropertyBackend but implements neither "
                    + "check(trials:seed:drawing:property:) nor check(trials:seed:sample:property:); "
                    + "implement check(trials:seed:drawing:property:)."
            )
        }
        return await check(
            trials: trials,
            seed: seed,
            drawing: { generator in
                if var xoshiro = generator as? Xoshiro {
                    let input = sample(&xoshiro)
                    generator = xoshiro
                    return input
                }
                var derived = BackendBridge.xoshiro(seededFrom: &generator)
                return sample(&derived)
            },
            property: property
        )
    }
}
