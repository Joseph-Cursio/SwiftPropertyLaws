import PropertyBased

/// Run `Semilattice` protocol laws over `Value` (PRD §4.3 v1.9 — kit-defined).
///
/// Default `laws: .all` runs the inherited `CommutativeMonoid` suite first
/// (which itself auto-recurses `Monoid` and transitively `Semigroup`) per
/// PRD §4.3 inheritance semantics; `.ownOnly` skips the inherited checks.
///
/// Returned-array order: inherited laws first (when `.all`) — Semigroup's
/// `combineAssociativity`, Monoid's `combineLeftIdentity` /
/// `combineRightIdentity`, then CommutativeMonoid's `combineCommutativity`
/// — followed by the one Semilattice own law: `combineIdempotence` (Strict).
///
/// **Generator caveat.** Idempotence checks run a single sample (no growth
/// concern); the inherited associativity check is three-way. Same per-trial
/// cost as the standalone Semigroup check.
@discardableResult
public func checkSemilatticePropertyLaws<
    Value: Semilattice & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
            try await checkCommutativeMonoidPropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(await checkCombineIdempotence(generator: generator, options: options))
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkCombineIdempotence<
    Value: Semilattice & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Semilattice.combineIdempotence",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                Value.combine(sample, sample) == sample
            },
            formatCounterexample: { sample, _ in
                let actual = Value.combine(sample, sample)
                return "x = \(sample); combine(x, x) = \(actual), expected x"
            }
        )
    )
}
