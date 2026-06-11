import PropertyBased

/// Brackets every public `check<Protocol>PropertyLaws` entry with the two
/// policy steps they all share — validate the replay environment *before* any
/// sampling, then enforce (throw) over the assembled results *after* — so that
/// policy lives in one place instead of being copy-pasted into each entry.
///
/// The `assemble` closure runs the suite's inherited + own law checks in
/// between and returns their `CheckResult`s; the runner verifies first, then
/// applies `PropertyLawViolation.throwIfViolations` with the caller's
/// enforcement mode.
func runPropertyLawSuite(
    options: LawCheckOptions,
    assemble: () async throws -> [CheckResult]
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = try await assemble()
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}
