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
    /// So the violation is now **visible**, recorded as a Swift Testing issue of `.warning` severity:
    /// the run prints it and the test still passes. Silence was never the tier's meaning; not
    /// failing the build was — PRD §4.2 says "warning by default; failure when `.strict` is
    /// requested".
    ///
    /// **The severity is the whole of that, and the first fix got it wrong.** `Issue.record`
    /// defaults to `.error`, and an error-severity issue marks the test failed whether or not
    /// anything throws. So the fix for silence made every sub-Strict violation fail its test under
    /// `.default`, while this comment, the message below and the README all said it did not. The
    /// repo's own tests could not notice: each wrapped the call in `withKnownIssue`, which absorbs
    /// an error just as readily as a warning.
    ///
    /// Swift Testing gained issue severity in Swift 6.3. An older toolchain has only the error
    /// form, and there the violation is still recorded — silence is the worse defect — under a
    /// message that says the test *is* marked failed.
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
        #if compiler(>=6.3)
        Issue.record(
            """
            \(result.protocolLaw) failed at \(result.tier) tier — recorded as a warning, not a \
            test failure, because enforcement is `.default` and only Strict-tier laws escalate. \
            Pass `.strict` to make it fail.

            \(ViolationFormatter.format(result))
            """,
            severity: .warning
        )
        #else
        Issue.record(
            """
            \(result.protocolLaw) failed at \(result.tier) tier. Enforcement is `.default`, so the \
            check did not throw — but Swift Testing before Swift 6.3 has no warning severity, so \
            recording the violation marks this test failed. Suppress the law in \
            `LawCheckOptions.suppressions` to accept it, or build with Swift 6.3 or later to see \
            it as a warning.

            \(ViolationFormatter.format(result))
            """
        )
        #endif
    }
}
