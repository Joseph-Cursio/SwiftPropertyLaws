import PropertyBased

/// Run `CommutativeMonoid` protocol laws over `Value` (PRD §4.3 v1.9 — kit-defined).
///
/// Default `laws: .all` runs the inherited `Monoid` suite first (which
/// itself auto-recurses `Semigroup`) per PRD §4.3 inheritance semantics;
/// `.ownOnly` skips the inherited checks.
///
/// Returned-array order: inherited laws first (when `.all`) — Semigroup's
/// `combineAssociativity`, then Monoid's `combineLeftIdentity` /
/// `combineRightIdentity` — followed by the one CommutativeMonoid own law:
/// `combineCommutativity` (Strict).
///
/// **Generator caveat shared with Semigroup / Monoid.** Some commutative
/// monoids grow under `combine` (e.g. multiset union); use small-input
/// generators so the per-trial allocation cost stays bounded.
@discardableResult
public func checkCommutativeMonoidPropertyLaws<
    Value: CommutativeMonoid & Equatable & Sendable,
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
            try await checkMonoidPropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(await checkCombineCommutativity(generator: generator, options: options))
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkCombineCommutativity<
    Value: CommutativeMonoid & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "CommutativeMonoid.combineCommutativity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (
                generator.run(using: &rng),
                generator.run(using: &rng)
            ) },
            property: { input in
                let (one, two) = input
                return Value.combine(one, two) == Value.combine(two, one)
            },
            formatCounterexample: { input, _ in
                let (one, two) = input
                let lhs = Value.combine(one, two)
                let rhs = Value.combine(two, one)
                return "x = \(one), y = \(two); "
                    + "combine(x, y) = \(lhs), "
                    + "combine(y, x) = \(rhs)"
            }
        )
    )
}
