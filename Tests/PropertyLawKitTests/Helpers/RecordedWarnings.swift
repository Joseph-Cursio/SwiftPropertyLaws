import Foundation
import Testing

/// The warnings `body` recorded, collected so a test can assert on them — including that there
/// were none.
///
/// Under `.default` enforcement a sub-Strict violation is recorded as a Swift Testing *warning*
/// (`PropertyLawViolation.throwIfViolations`), and a warning does not fail a test. So neither "the
/// violation surfaced" nor "nothing surfaced" can be checked by letting the run proceed: both
/// pass. `withKnownIssue`'s matcher is the only public hook that sees an issue as it is recorded,
/// and this uses it to collect warnings and nothing else.
///
/// **That restriction is the point.** An unmatched `withKnownIssue` — how these call sites were
/// written before — absorbs *every* issue in its body. A failed `#expect` and a thrown error became
/// known issues too, so the assertions inside those blocks could not fail, and a test named "does
/// not throw by default" could not see a throw. Here an error-severity issue is not matched and
/// fails the test, and an error thrown by `body` propagates.
///
/// `isIntermittent` is what lets an empty result be asserted; without it `withKnownIssue` itself
/// fails when nothing is recorded. Each collected warning still appears in the run's output, as a
/// known issue.
func recordedWarnings(
    isolation: isolated (any Actor)? = #isolation,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ body: () async throws -> Void
) async rethrows -> [String] {
    let log = WarningLog()
    try await withKnownIssue(
        "collected by recordedWarnings(_:)",
        isIntermittent: true,
        isolation: isolation,
        sourceLocation: sourceLocation,
        body,
        matching: { issue in
            #if compiler(>=6.3)
            guard issue.severity == .warning else { return false }
            #else
            // No severity before Swift 6.3, and the kit records at `.error` there. Collect what
            // `Issue.record` produced, which still lets a failed `#expect` or a thrown error through.
            guard case .unconditional = issue.kind else { return false }
            #endif
            log.append(issue.comments.map(\.rawValue).joined(separator: "\n"))
            return true
        }
    )
    return log.messages
}

/// The law each warning reports. The kit's message opens with `<law> failed at`, so a test can
/// assert *which* laws surfaced rather than only that something did.
func lawsReported(in warnings: [String]) -> [String] {
    warnings.map { warning in
        warning.range(of: " failed at ").map { String(warning[..<$0.lowerBound]) } ?? warning
    }
}

/// The matcher is `@Sendable` and may run on whichever thread recorded the issue.
private final class WarningLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    func append(_ message: String) {
        lock.withLock { recorded.append(message) }
    }

    var messages: [String] {
        lock.withLock { recorded }
    }
}
