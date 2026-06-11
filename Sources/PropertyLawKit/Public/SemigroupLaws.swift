import PropertyBased

/// Run `Semigroup` protocol laws over `Value` (PRD §4.3 v1.8 — kit-defined).
///
/// One Strict-tier algebraic law — a violation is a bug:
/// - `combineAssociativity` — `combine(combine(a, b), c) == combine(a, combine(b, c))`
///
/// `Semigroup` does not refine `Equatable` in the kit's protocol decl
/// (the law check requires `Equatable`, but a type can declare `Semigroup`
/// without conforming to `Equatable` — the unverified case). The signature
/// here pins both because the law can't be checked otherwise.
///
/// **Generator caveat for unbounded combine.** Some semigroups grow
/// without bound under `combine` (e.g. string concat — `"a" • "b" • "c"`
/// produces a 3-char string from 1-char inputs). For three-way
/// associativity sampling, prefer generators producing small inputs
/// (`Gen<Character>.letterOrNumber.string(of: 0...4)` rather than
/// `0...64`) so the trial budget doesn't slow under nested allocation.
@discardableResult
public func checkSemigroupPropertyLaws<
    Value: Semigroup & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkCombineAssociativity(generator: generator, options: options)
    ]
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkCombineAssociativity<
    Value: Semigroup & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Semigroup.combineAssociativity",
        generator: generator,
        options: options,
        property: { one, two, three in
            let leftGrouped = Value.combine(Value.combine(one, two), three)
            let rightGrouped = Value.combine(one, Value.combine(two, three))
            return leftGrouped == rightGrouped
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = Value.combine(Value.combine(one, two), three)
            let rhs = Value.combine(one, Value.combine(two, three))
            return "x = \(one), y = \(two), z = \(three); "
                + "combine(combine(x, y), z) = \(lhs), "
                + "combine(x, combine(y, z)) = \(rhs)"
        }
    )
}
