/// Cross-cutting options shared by every `checkXxxPropertyLaws` function.
///
/// Bundled into a struct so the public surface stays small and uniform —
/// `budget`, `enforcement`, `seed`, `suppressions`, `backend`, and the
/// replay-validation pair are universally meaningful and grow together.
/// Per-protocol concerns (`laws: LawSelection`, Codable's
/// `config: CodableLawConfig`, Sequence's `passing`) remain separate
/// parameters because they vary by check.
///
/// Not `Hashable` — the `backend: any PropertyBackend` field is an existential,
/// and forcing every backend implementation to be `Hashable` would foreclose
/// reasonable backends. Tests that compare options compare field-by-field.
public struct LawCheckOptions: Sendable {
    public var budget: TrialBudget
    public var enforcement: EnforcementMode
    public var seed: Seed?

    /// Per-call opt-outs (PRD §4.7). Order is irrelevant; the first matching
    /// `LawIdentifier` wins. Suppressions never escalate to a throw, regardless
    /// of `enforcement`.
    public var suppressions: [LawSuppression]

    /// Property-based backend that drives the per-trial loop (PRD §4.5).
    /// Default is `SwiftPropertyBasedBackend` — the only backend v1 ships.
    /// The protocol stays open for future alternatives. Only per-trial laws
    /// reach the backend: aggregate-mode laws (`Hashable.distribution`,
    /// `InteractionInvariant.isFalsifiable`), the equal-value laws under
    /// `equalValuePairing`, and walks over an `Enumeration` draw from the
    /// kit's own `Xoshiro` and record this backend's identifier only in the
    /// environment fingerprint. See "What the backend does not drive" on
    /// ``PropertyBackend``.
    public var backend: any PropertyBackend

    /// When non-nil, the kit verifies this fingerprint matches the live one
    /// (`Environment.current(backend:)`, plus `scheduling` in a suite that
    /// honours it) before running and throws
    /// `ReplayEnvironmentMismatch` on divergence (PRD §4.6). Pair with
    /// `seed` when replaying a stored CI artifact.
    public var expectedReplayEnvironment: Environment?

    /// Strictness applied to `expectedReplayEnvironment` matching. Default
    /// is `.exact`; relaxations exist for legitimate toolchain bumps.
    public var replayRelaxation: EnvironmentRelaxation

    /// Opt-in flag for NaN-domain `FloatingPoint` laws (PRD §4.3).
    /// Default `false` runs the always-on FloatingPoint laws (which guard
    /// non-finite samples internally). `true` adds five NaN-specific Strict
    /// laws — `nanIsNaN`, `nanInequality`, `nanPropagatesAddition`,
    /// `nanPropagatesMultiplication`, `nanComparisonIsUnordered` — that
    /// exercise IEEE-754 NaN behavior. Other protocol checks (Equatable,
    /// Hashable, etc.) are unaffected; for those, supply a finite-only
    /// generator if your value type is floating-point.
    public var allowNaN: Bool

    /// How `Hashable.equalityConsistency`, `Equatable.transitivity` and
    /// `Comparable.antisymmetry` pair their draws. Default `.independent`;
    /// `.everyPairOfDraws` compares every draw of the budget with every other,
    /// which finds equal values a wide generator otherwise never pairs up. See
    /// ``EqualValuePairing``.
    public var equalValuePairing: EqualValuePairing

    /// How a virtual-time run orders its runnable jobs. Default `.fifo`. Only
    /// the laws that run in virtual time honour it (today
    /// `checkTimedAsyncSequencePropertyLaws` and `checkAsyncLifetimePropertyLaws`);
    /// every other law ignores it and keeps its `.fifo` draws, fingerprint and
    /// failure text. See ``SchedulingStrategy``.
    public var scheduling: SchedulingStrategy

    /// Whether the suite being run honours `scheduling`. Only the virtual-time
    /// entry points set it to `true`. The fingerprint records `scheduling` only
    /// when this is `true`, so a sync law run with `.seeded` keeps a `.fifo`
    /// fingerprint and failure text. The drivers (stamping) and
    /// `ReplayEnvironmentValidator` (checking) both read it through
    /// `Environment.current(options:)`, so they cannot disagree.
    package var schedulingIsInEffect: Bool = false

    public init(
        budget: TrialBudget = .standard,
        enforcement: EnforcementMode = .default,
        seed: Seed? = nil,
        suppressions: [LawSuppression] = [],
        backend: any PropertyBackend = SwiftPropertyBasedBackend(),
        expectedReplayEnvironment: Environment? = nil,
        replayRelaxation: EnvironmentRelaxation = .exact,
        allowNaN: Bool = false,
        equalValuePairing: EqualValuePairing = .independent,
        scheduling: SchedulingStrategy = .fifo
    ) {
        self.budget = budget
        self.enforcement = enforcement
        self.seed = seed
        self.suppressions = suppressions
        self.backend = backend
        self.expectedReplayEnvironment = expectedReplayEnvironment
        self.replayRelaxation = replayRelaxation
        self.allowNaN = allowNaN
        self.equalValuePairing = equalValuePairing
        self.scheduling = scheduling
    }
}
