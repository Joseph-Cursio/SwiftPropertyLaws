import PropertyBased

/// Run `Group` protocol laws over `Value` (PRD §4.3 v1.9 — kit-defined).
///
/// Default `laws: .all` runs the inherited `Monoid` suite first (which
/// itself auto-recurses `Semigroup`) per PRD §4.3 inheritance semantics;
/// `.ownOnly` skips the inherited checks.
///
/// Returned-array order: inherited laws first (when `.all`) — Semigroup's
/// `combineAssociativity`, then Monoid's `combineLeftIdentity` /
/// `combineRightIdentity` — followed by the two Group own laws:
/// `combineLeftInverse`, `combineRightInverse` (both Strict).
///
/// **Generator caveat.** Some groups grow under repeated `combine` (e.g.
/// free groups over a generator set); the inverse laws use single samples
/// so allocation isn't multiplied, but the inherited associativity check
/// is three-way — same per-trial cost as the standalone Semigroup check.
@discardableResult
public func checkGroupPropertyLaws<
    Value: Group & Equatable & Sendable,
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
                try await checkMonoidPropertyLaws(
                    for: type,
                    using: generator,
                    options: $0
                )
            })
        }
        results.append(contentsOf: [
            await checkCombineLeftInverse(generator: generator, options: options),
            await checkCombineRightInverse(generator: generator, options: options)
        ])
        return results
    }
}

private func checkCombineLeftInverse<
    Value: Group & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Group.combineLeftInverse",
        generator: generator,
        options: options,
        property: { sample in
            Value.combine(Value.inverse(sample), sample) == Value.identity
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(Value.inverse(sample), sample)
            return "x = \(sample); combine(inverse(x), x) = \(actual), expected .identity"
        }
    )
}

private func checkCombineRightInverse<
    Value: Group & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Group.combineRightInverse",
        generator: generator,
        options: options,
        property: { sample in
            Value.combine(sample, Value.inverse(sample)) == Value.identity
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(sample, Value.inverse(sample))
            return "x = \(sample); combine(x, inverse(x)) = \(actual), expected .identity"
        }
    )
}
