/// A declarative opt-out for a single protocol law on a single check call (PRD §4.7).
///
/// Two kinds:
/// - `.skip` — don't run the check at all. Reported as `.suppressed` with `trials: 0`.
/// - `.intentionalViolation` — run the check; if it would fail, rewrite the
///   outcome to `.expectedViolation`. If it unexpectedly passes the kit reports
///   `.passed` (no surprise-pass signal in M3; see PRD §4.7).
///
/// Suppressions do not throw under any `EnforcementMode` — they are explicit
/// policy. They appear in the test report (formatted with a distinct glyph)
/// so reviewers can spot growth in the suppression list during code review.
public struct LawSuppression: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case skip
        case intentionalViolation
    }

    public let identifier: LawIdentifier
    public let kind: Kind
    public let reason: String

    public init(identifier: LawIdentifier, kind: Kind, reason: String) {
        self.identifier = identifier
        self.kind = kind
        self.reason = reason
    }

    /// Does not run the law. Its result reports `.suppressed` with `reason`.
    public static func skip(_ identifier: LawIdentifier, reason: String) -> Self {
        Self(identifier: identifier, kind: .skip, reason: reason)
    }

    /// Runs the law and expects it to fail. A failure is reported as an expected violation with `reason`
    /// instead of being thrown.
    public static func intentionalViolation(
        _ identifier: LawIdentifier,
        reason: String
    ) -> Self {
        Self(identifier: identifier, kind: .intentionalViolation, reason: reason)
    }
}
