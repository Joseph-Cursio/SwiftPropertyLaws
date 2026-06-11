import PropertyBased

/// Run `Monoid` protocol laws over `Value` (PRD §4.3 v1.8 — kit-defined).
///
/// Default `laws: .all` runs the inherited `Semigroup` suite first per
/// PRD §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: inherited laws first (when `.all`), then the
/// two Monoid own laws — `combineLeftIdentity`, `combineRightIdentity`
/// (both Strict).
///
/// **Generator caveat shared with Semigroup.** Some monoids grow under
/// `combine` (e.g. string concat). Identity laws use single samples so
/// allocation isn't multiplied, but the inherited associativity check
/// is three-way; same per-trial cost as the standalone Semigroup check.
@discardableResult
public func checkMonoidPropertyLaws<
    Value: Monoid & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkSemigroupPropertyLaws(
                    for: type,
                    using: generator,
                    options: $0
                )
            })
        }
        results.append(contentsOf: [
            await checkCombineLeftIdentity(generator: generator, options: options),
            await checkCombineRightIdentity(generator: generator, options: options)
        ])
        return results
    }
}

private func checkCombineLeftIdentity<
    Value: Monoid & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Monoid.combineLeftIdentity",
        generator: generator,
        options: options,
        property: { sample in
            Value.combine(Value.identity, sample) == sample
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(Value.identity, sample)
            return "x = \(sample); combine(.identity, x) = \(actual), expected x"
        }
    )
}

private func checkCombineRightIdentity<
    Value: Monoid & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Monoid.combineRightIdentity",
        generator: generator,
        options: options,
        property: { sample in
            Value.combine(sample, Value.identity) == sample
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(sample, Value.identity)
            return "x = \(sample); combine(x, .identity) = \(actual), expected x"
        }
    )
}
