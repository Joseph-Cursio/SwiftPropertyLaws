import PropertyBased

/// Run `Comparable` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Equatable` suite first per PRD
/// §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: Equatable laws (when `.all`) then Comparable laws —
/// `antisymmetry` (Strict), `transitivity` (Strict), `totality` (Conventional),
/// `operatorConsistency` (Strict).
@discardableResult
public func checkComparablePropertyLaws<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
            try await checkEquatablePropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(contentsOf: [
        await checkAntisymmetry(generator: generator, options: options),
        await checkTransitivity(generator: generator, options: options),
        await checkTotality(generator: generator, options: options),
        await checkOperatorConsistency(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkAntisymmetry<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Comparable.antisymmetry",
        generator: generator,
        options: options,
        property: { first, second in
            !(first <= second && second <= first) || (first == second)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); x <= y and y <= x but x != y"
        }
    )
}

private func checkTransitivity<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Comparable.transitivity",
        generator: generator,
        options: options,
        property: { first, second, third in
            !(first <= second && second <= third) || (first <= third)
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x <= y and y <= z but !(x <= z)"
        }
    )
}

private func checkTotality<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Comparable.totality",
        tier: .conventional,
        generator: generator,
        options: options,
        property: { first, second in
            first <= second || second <= first
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); neither x <= y nor y <= x (NaN-like)"
        }
    )
}

// `<=`, `>`, `>=` are derived from `<` by Comparable's protocol witnesses, so
// this check can't catch "user overrode `<=` inconsistently with `<`" through
// generic dispatch. It DOES catch "user's `<` is broken in a way that makes
// the derived operators internally inconsistent" — e.g. `<` returning true
// for both directions of a pair makes `x < y` and `!(x <= y)` simultaneously
// true.
private func checkOperatorConsistency<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Comparable.operatorConsistency",
        generator: generator,
        options: options,
        property: { first, second in
            operatorConsistencyCounterexample(for: (first, second)) == nil
        },
        formatCounterexample: { first, second, _ in
            operatorConsistencyCounterexample(for: (first, second)) ?? "<no counterexample>"
        }
    )
}

private func operatorConsistencyCounterexample<Value: Comparable>(
    for input: (Value, Value)
) -> String? {
    let (first, second) = input
    let lessThan = first < second
    let greaterThan = first > second
    let lessOrEqual = first <= second
    let greaterOrEqual = first >= second
    if greaterThan != (second < first) {
        return "x = \(first), y = \(second); x > y → \(greaterThan) "
            + "but y < x → \(second < first)"
    }
    if greaterOrEqual != (second <= first) {
        return "x = \(first), y = \(second); x >= y → \(greaterOrEqual) "
            + "but y <= x → \(second <= first)"
    }
    if lessThan && !lessOrEqual {
        return "x = \(first), y = \(second); x < y but !(x <= y)"
    }
    return nil
}
