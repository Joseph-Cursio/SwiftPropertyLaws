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

    public internal(set) var protocolLaw: String
    public internal(set) var tier: StrictnessTier
    public internal(set) var trials: Int
    public internal(set) var seed: Seed
    public internal(set) var environment: Environment
    public internal(set) var outcome: Outcome

    /// Inputs that came close to violating the law.
    /// Per PRD §4.6: `nil` means the backend doesn't track near-misses (distinct from `[]`).
    /// M1's loop doesn't track near-misses; field is always `nil` until M5.
    public internal(set) var nearMisses: [String]?

    /// Distribution / boundary metadata. Reserved; see PRD §4.6. M1 always reports `nil`.
    public internal(set) var coverageHints: CoverageHints?

    /// The pre-shrink counterexample, when shrinking reduced a `.failed` to a
    /// smaller still-failing input (v2.4). `outcome`'s `counterexample` always
    /// holds the *minimal* form; `shrunkFrom` holds the original first-failing
    /// form. `nil` when no shrinking happened (`shrinkSteps == 0`).
    public internal(set) var shrunkFrom: String?

    /// Number of shrink steps applied to reach the minimal counterexample
    /// (v2.4). `0` when the law supplied no shrinker, the carrier isn't
    /// shrinkable, or the first failing input was already minimal.
    public internal(set) var shrinkSteps: Int

    /// How much of a bounded input space this check walked (Slice 1 of the
    /// enumeration work). `nil` — the case for every sampled law — means the
    /// check does not know its input space, which is distinct from knowing it
    /// and having covered none of it. See ``SpaceCoverage``.
    public internal(set) var coverage: SpaceCoverage?

    /// How many times a **conditional** law's antecedent fired.
    ///
    /// `nil` — the case for every unconditional law — means the question does
    /// not apply, not that the answer is zero. A law written
    /// `!(antecedent) || consequent` returns `true` whenever the antecedent
    /// fails, so a run that never reached the case reports a pass; this is the
    /// number that says whether that happened.
    ///
    /// **It is a floor, not a verdict.** Zero means the law tested nothing. A
    /// small non-zero number means the law applied, and says nothing about
    /// whether it applied to a case that could have refuted it — measured on a
    /// non-transitive `==` over a 100-value domain, the antecedent fired twice
    /// per thousand trials and the refuting configuration zero times. Reported
    /// rather than enforced for that reason, following the same discipline as
    /// ``SpaceCoverage``: surface the fact, do not fabricate a verdict.
    public internal(set) var applications: Int?

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
        shrinkSteps: Int = 0,
        coverage: SpaceCoverage? = nil,
        applications: Int? = nil
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
        self.coverage = coverage
        self.applications = applications
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
