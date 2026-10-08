/// How the three laws that need equal values pair up their draws.
///
/// `Hashable.equalityConsistency`, `Equatable.transitivity` and
/// `Comparable.antisymmetry` test something only when two drawn values are equal
/// (or, for antisymmetry, equivalent under the order). Drawn independently per
/// trial, a wide generator almost never produces such a pair, and the law passes
/// having tested nothing.
///
/// Comparing every draw with every other draw finds the equal pairs a budget
/// already contains — the birthday collisions — instead of hoping one trial
/// happens to draw two. It is quadratic in the budget, which is why it is opt-in.
///
/// Every other law ignores this setting, and so does a walk over an
/// `Enumeration`, which reaches every pair by construction already.
public enum EqualValuePairing: Sendable, Hashable {
    /// Each trial draws its own values. The default, and what every other law does.
    case independent

    /// Draw the budget once and compare each draw with every earlier one: 1 000
    /// draws make 499 500 pairs. Transitivity follows the equal pairs it finds
    /// into chains rather than testing every triple.
    ///
    /// The draws come from one seeded stream, so the seed replays the same pool.
    /// The pool is drawn by the kit, not by `LawCheckOptions.backend` — the same
    /// posture as `Hashable.distribution`, the other law that judges a whole
    /// budget at once.
    case everyPairOfDraws

    /// Compare each draw with only the `window` draws before it — linear rather
    /// than quadratic, and correspondingly fewer pairs.
    case recentDraws(window: Int)

    /// How many earlier draws each new draw is compared with, or `nil` for
    /// independent trials.
    var lookback: Int? {
        switch self {
        case .independent: return nil
        case .everyPairOfDraws: return .max
        case .recentDraws(let window): return max(window, 1)
        }
    }
}
