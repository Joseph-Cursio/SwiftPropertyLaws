/// How much of a bounded input space a check actually walked.
///
/// This is the field that lets a result stop implying coverage it does not
/// have. `TrialBudget.exhaustive(10_000)` names a *trial count* — ten thousand
/// random draws — and a reader is entitled to hear "exhaustive" as a statement
/// about the input space. It is not one. A walk over an ``Enumeration`` can make
/// that statement, so it reports it here as a fact rather than leaving it to be
/// inferred from a budget's name.
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
