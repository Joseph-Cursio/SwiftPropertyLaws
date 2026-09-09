/// How much sampling effort a law gets (PRD §4.4).
///
/// **These are effort tiers, not coverage claims.** Every case here names a
/// number of random draws; none of them says anything about the input space,
/// because a generator has no space to be exhaustive over. A law that wants to
/// state coverage takes an `Enumeration` and reports ``SpaceCoverage``.
///
/// That distinction used to be blurred by a case called `exhaustive`, which was
/// `custom(trials:)` under a name that claimed the opposite — the kit's own
/// instance of the defect its notes keep recording, a default presented as a
/// guarantee. It is now ``thorough``, which describes the effort rather than
/// promising a result.
public enum TrialBudget: Sendable, Hashable {
    /// 100 draws. A smoke test.
    case sanity
    /// 1 000 draws. The default.
    case standard
    /// 10 000 draws — the most effort the kit spends by default, for nightly
    /// and release branches.
    ///
    /// Deliberately payload-free: a tier with a count is just ``custom(trials:)``
    /// wearing a tier's name, which is how the old spelling came to have two
    /// ways of saying the same thing.
    case thorough
    /// An explicit draw count.
    case custom(trials: Int)

    public var trialCount: Int {
        switch self {
        case .sanity: return 100
        case .standard: return 1_000
        case .thorough: return 10_000
        case .custom(let count): return count
        }
    }
}

extension TrialBudget {
    /// - Warning: Renamed. The name claimed a property of the *input space* and
    ///   delivered a property of the *loop* — ten thousand random draws, with
    ///   nothing exhausted. Use ``thorough`` for the tier, or
    ///   ``custom(trials:)`` for a specific count. For a budget that genuinely
    ///   covers its input space, walk an `Enumeration` instead and read
    ///   ``SpaceCoverage``.
    @available(*, deprecated, message: """
        'exhaustive' named a trial count, not coverage of an input space. \
        Use .thorough for the 10 000-draw tier, .custom(trials:) for another count, \
        or walk an Enumeration for a run that can actually report its coverage.
        """)
    public static func exhaustive(_ trials: Int = 10_000) -> TrialBudget {
        .custom(trials: trials)
    }
}
