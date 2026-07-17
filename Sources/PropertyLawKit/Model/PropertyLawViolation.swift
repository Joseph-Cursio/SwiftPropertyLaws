import Testing

public struct PropertyLawViolation: Error, Sendable, CustomStringConvertible {
    public let results: [CheckResult]

    public init(results: [CheckResult]) {
        self.results = results
    }

    public var description: String {
        results.map(ViolationFormatter.format).joined(separator: "\n\n")
    }

    /// Escalates what the enforcement mode says must fail, and — crucially — **reports what it says
    /// must not.**
    ///
    /// A Conventional-tier violation under `.default` does not throw, and that is correct: the tier
    /// exists so a type can consciously decline a customary law. But *not throwing* was implemented
    /// as *not saying anything*, and combined with `@discardableResult` on every `checkXxx…` entry
    /// point, the idiomatic spelling
    ///
    ///     checkCodablePropertyLaws(for: FileResponse.self, using: …, config: .init(codec: .iso8601))
    ///
    /// swallowed a genuine violation in total silence. A lossy codec — one that cannot round-trip its
    /// own dates — reported as a pass. That is the worst thing a law kit can do, because the *entire*
    /// value of the kit is that it tells you when a law is broken, and here it knew and said nothing.
    ///
    /// So the tier semantics are untouched — the test still does not fail — but the violation is now
    /// **visible**, recorded as a non-fatal Swift Testing issue. Silence was never the tier's
    /// meaning; not failing the build was.
    ///
    /// `.suppressed` and `.expectedViolation` are deliberately *not* reported. They are explicit
    /// policy — someone wrote down that this law does not hold and why — and re-surfacing them would
    /// make the suppression mechanism useless (PRD §4.7). Only `.failed` outcomes speak here.
    static func throwIfViolations(in results: [CheckResult], enforcement: EnforcementMode) throws {
        var escalating: [CheckResult] = []

        for result in results where result.isViolation {
            if enforcement.shouldThrow(for: result.tier) {
                escalating.append(result)
            } else {
                recordNonFatal(result)
            }
        }

        guard !escalating.isEmpty else { return }
        throw PropertyLawViolation(results: escalating)
    }

    /// A violation the enforcement mode has decided not to fail the test over — surfaced rather than
    /// dropped. Outside a running test `Issue.record` is a no-op, so this is safe to call from any
    /// context the kit is used in.
    private static func recordNonFatal(_ result: CheckResult) {
        Issue.record(
            """
            \(result.protocolLaw) failed at \(result.tier) tier — not failing this test, \
            because enforcement is `.default` and only Strict-tier laws escalate. Pass \
            `.strict` to make it fail.

            \(ViolationFormatter.format(result))
            """
        )
    }
}
