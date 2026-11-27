/// Single boundary that every public `checkXxxPropertyLaws` function calls
/// before paying any trial budget — implements the PRD §4.6 environment
/// fingerprint replay validation.
///
/// No-op when `options.expectedReplayEnvironment == nil`. Otherwise compares
/// the expected fingerprint against `Environment.current(options:)` under the
/// caller's `replayRelaxation` policy and throws `ReplayEnvironmentMismatch`
/// when they don't match.
///
/// **The same constructor the drivers stamp with.** If this built `actual`
/// from `current(backend:)`, which never carries the scheduling strategy, a
/// seeded result's own fingerprint could never be replayed, and a FIFO
/// fingerprint replayed under `.seeded` would match and silently test a
/// different run.
internal enum ReplayEnvironmentValidator {
    static func verify(_ options: LawCheckOptions) throws {
        guard let expected = options.expectedReplayEnvironment else { return }
        let actual = Environment.current(options: options)
        if options.replayRelaxation.matches(expected: expected, actual: actual) { return }
        throw ReplayEnvironmentMismatch(expected: expected, actual: actual)
    }
}
