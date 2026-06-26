public struct CheckResult: Sendable, Hashable {
    public enum Outcome: Sendable, Hashable {
        case passed
        case failed(counterexample: String)

        /// The check was skipped under a `.skip` suppression. `trials` will be 0.
        case suppressed(reason: String)

        /// The check failed, but a `.intentionalViolation` suppression matched —
        /// the failure is the documented design and not a regression.
        case expectedViolation(reason: String, counterexample: String)
    }

    public let protocolLaw: String
    public let tier: StrictnessTier
    public let trials: Int
    public let seed: Seed
    public let environment: Environment
    public let outcome: Outcome

    /// Inputs that came close to violating the law.
    /// Per PRD §4.6: `nil` means the backend doesn't track near-misses (distinct from `[]`).
    /// M1's loop doesn't track near-misses; field is always `nil` until M5.
    public let nearMisses: [String]?

    /// Distribution / boundary metadata. Reserved; see PRD §4.6. M1 always reports `nil`.
    public let coverageHints: CoverageHints?

    /// The pre-shrink counterexample, when shrinking reduced a `.failed` to a
    /// smaller still-failing input (v2.4). `outcome`'s `counterexample` always
    /// holds the *minimal* form; `shrunkFrom` holds the original first-failing
    /// form. `nil` when no shrinking happened (`shrinkSteps == 0`).
    public let shrunkFrom: String?

    /// Number of shrink steps applied to reach the minimal counterexample
    /// (v2.4). `0` when the law supplied no shrinker, the carrier isn't
    /// shrinkable, or the first failing input was already minimal.
    public let shrinkSteps: Int

    public init(
        protocolLaw: String,
        tier: StrictnessTier,
        trials: Int,
        seed: Seed,
        environment: Environment,
        outcome: Outcome,
        nearMisses: [String]? = nil,
        coverageHints: CoverageHints? = nil,
        shrunkFrom: String? = nil,
        shrinkSteps: Int = 0
    ) {
        self.protocolLaw = protocolLaw
        self.tier = tier
        self.trials = trials
        self.seed = seed
        self.environment = environment
        self.outcome = outcome
        self.nearMisses = nearMisses
        self.coverageHints = coverageHints
        self.shrunkFrom = shrunkFrom
        self.shrinkSteps = shrinkSteps
    }

    public var isViolation: Bool {
        if case .failed = outcome { return true }
        return false
    }

    public var counterexample: String? {
        switch outcome {
        case .failed(let counterexample):
            return counterexample
        case .expectedViolation(_, let counterexample):
            return counterexample
        case .passed, .suppressed:
            return nil
        }
    }
}

public struct CoverageHints: Sendable, Hashable {
    public let inputClasses: [String: Int]
    public let boundaryHits: [String: Int]

    public init(inputClasses: [String: Int], boundaryHits: [String: Int]) {
        self.inputClasses = inputClasses
        self.boundaryHits = boundaryHits
    }
}
