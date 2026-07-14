import PropertyBased

/// Runs an inherited protocol's `check…PropertyLaws` suite and folds its
/// outcome into a `[CheckResult]` without rethrowing.
///
/// Every `check<Protocol>PropertyLaws` that chains its parent under
/// `laws: .all` previously hand-rolled an identical private
/// `collectInherited<Parent>` function: rebuild `LawCheckOptions` with
/// `enforcement: .default` (so the parent's violations are *collected*, not
/// thrown — the child decides enforcement once, over the merged results),
/// invoke the parent check, and convert a thrown `PropertyLawViolation` back
/// into its `.results`. This helper hosts that shared body once; call sites
/// pass the single varying piece — the parent invocation — as `check`, which
/// receives the rebuilt options.
///
/// The closure form also covers the two non-uniform cases the old per-file
/// functions handled: collection suites that thread `sequenceOptions:` into
/// the parent call (captured by the closure) and `SignedInteger`'s two
/// independent parent chains (two separate calls).
func collectingInheritedLaws(
    rebasing options: LawCheckOptions,
    _ check: (LawCheckOptions) async throws -> [CheckResult]
) async -> [CheckResult] {
    // **Mutate a copy.** The rebuild this replaces named five of `LawCheckOptions`' EIGHT fields,
    // so `expectedReplayEnvironment`, `replayRelaxation` and `allowNaN` were silently reset to
    // their defaults for every inherited law — a caller who set `allowNaN: true` had it quietly
    // ignored on the parent protocol's laws. The initialiser's parameters have defaults, so the
    // omission compiled and nothing went red.
    //
    // Only `enforcement` is meant to change here; that is what "rebasing" means.
    var inheritedOptions = options
    inheritedOptions.enforcement = .default
    do {
        return try await check(inheritedOptions)
    } catch let violation as PropertyLawViolation {
        return violation.results
    } catch {
        return []
    }
}
