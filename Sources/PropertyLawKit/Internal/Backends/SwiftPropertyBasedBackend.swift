import PropertyBased

/// Default `PropertyBackend` — a thin wrapper around the same Xoshiro-driven
/// trial loop the kit has used since M1. Shrinking is not yet exercised
/// (M5+ scope); this backend reports the first failing input verbatim.
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
        var ranTrials = 0
        // `max` because a negative count is a caller's mistake, not a reason to trap: the law
        // drivers refuse such a budget with a named failure (`CheckPreflight`), and a direct caller
        // gets an empty run it can see in `trialsRun`.
        for _ in 0..<max(trials, 0) {
            ranTrials += 1
            let input = sample(&rng)
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
