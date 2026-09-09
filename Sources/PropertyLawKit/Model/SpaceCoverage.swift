/// How much of a bounded input space a check actually walked.
///
/// This is the field that lets a result stop implying coverage it does not
/// have. A `TrialBudget` is *effort* — a number of random draws — and says
/// nothing about the input space, because a generator has no space to be
/// measured against. A walk over an ``Enumeration`` does have one, so it reports
/// the fraction it covered here as a fact rather than leaving a reader to infer
/// it from how hard the run tried.
///
/// The kit used to spell its largest budget `exhaustive`, which invited exactly
/// that inference; it is now `TrialBudget.thorough`, and this type carries the
/// claim the old name was borrowing.
///
/// Follows the same nil-versus-empty discipline as `CheckResult.nearMisses`:
/// `nil` on a result means **this check does not know its input space** — true
/// of every sampled law, and not the same as knowing the space and having
/// covered none of it.
public struct SpaceCoverage: Sendable, Hashable {
    /// Cases actually examined. On a failure this is where the walk stopped,
    /// not how much of the space was reachable.
    public let casesRun: Int

    /// Size of the space before any `Enumeration.prefix(_:)` truncation, so a
    /// capped walk reports the shortfall rather than claiming completeness.
    public let spaceSize: Int

    public init(casesRun: Int, spaceSize: Int) {
        self.casesRun = casesRun
        self.spaceSize = spaceSize
    }

    /// Whether every case in the space was examined. Only meaningful on a
    /// passing result — a walk that stopped early stopped because it found
    /// something, not because it ran out.
    public var isComplete: Bool { casesRun >= spaceSize }
}
