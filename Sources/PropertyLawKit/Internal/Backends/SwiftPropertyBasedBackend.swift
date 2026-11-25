import PropertyBased

/// Default `PropertyBackend` — a thin wrapper around the same Xoshiro-driven
/// trial loop the kit has used since M1. Shrinking is not yet exercised
/// (M5+ scope); this backend reports the first failing input verbatim.
///
/// It implements both sampling requirements over one loop, and both draw from
/// a `Xoshiro` started at `seed`, so a seed produces the same inputs whichever
/// requirement a caller uses.
public struct SwiftPropertyBasedBackend: PropertyBackend {

    public let identifier: String

    public init(identifier: String = "swift-property-based") {
        self.identifier = identifier
    }

    public func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        sample: @Sendable (inout Xoshiro) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        var rng = seed?.makeXoshiro() ?? Xoshiro()
        let initialSeed = Seed(xoshiro: rng)
        return await Self.loop(
            trials: trials, initialSeed: initialSeed, generator: &rng, sample: sample, property: property
        )
    }

    // Disfavored like the requirement, so an unlabeled trailing sampling
    // closure still resolves to `sample:` on this concrete type.
    @_disfavoredOverload
    public func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        drawing: @Sendable (inout any SeededRandomNumberGenerator) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        let start = seed?.makeXoshiro() ?? Xoshiro()
        var rng: any SeededRandomNumberGenerator = start
        return await Self.loop(
            trials: trials, initialSeed: Seed(xoshiro: start), generator: &rng, sample: drawing, property: property
        )
    }

    /// The trial loop both requirements share; `Generator` is `Xoshiro` or the
    /// existential holding one.
    private static func loop<Generator, Input: Sendable>(
        trials: Int,
        initialSeed: Seed,
        generator: inout Generator,
        sample: @Sendable (inout Generator) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        var ranTrials = 0
        // `max` because a negative count is a caller's mistake, not a reason to trap: the law
        // drivers refuse such a budget with a named failure (`CheckPreflight`), and a direct caller
        // gets an empty run it can see in `trialsRun`.
        for _ in 0..<max(trials, 0) {
            ranTrials += 1
            let input = sample(&generator)
            do {
                let passed = try await property(input)
                if !passed {
                    return .failed(
                        trialsRun: ranTrials,
                        initialSeed: initialSeed,
                        failingInput: input,
                        thrownError: nil
                    )
                }
            } catch {
                return .failed(
                    trialsRun: ranTrials,
                    initialSeed: initialSeed,
                    failingInput: input,
                    thrownError: ErrorBox(error)
                )
            }
        }
        return .passed(trialsRun: ranTrials, initialSeed: initialSeed)
    }
}
