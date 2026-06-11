import PropertyBased

/// Run the four `Equatable` protocol laws over `Value` (PRD §4.3).
///
/// All four laws are Strict tier — a violation is a bug. Equatable has no
/// inherited protocol law suite, so `LawSelection` is not exposed here.
///
/// **Coverage hints (M5).** Optional `coverage:` classifier populates
/// `CheckResult.coverageHints` on `Equatable.reflexivity` (the only
/// unary-input law in this suite). Pair / triple-input laws (symmetry,
/// transitivity, negationConsistency) silently ignore the classifier.
@discardableResult
public func checkEquatablePropertyLaws<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    coverage: AnyCoverageClassifier<Value>? = nil
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkReflexivity(generator: generator, options: options, coverage: coverage),
        await checkSymmetry(generator: generator, options: options),
        await checkTransitivity(generator: generator, options: options),
        await checkNegationConsistency(generator: generator, options: options)
    ]
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkReflexivity<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    coverage: AnyCoverageClassifier<Value>?
) async -> CheckResult {
    let classify: (@Sendable (Value) -> (classes: Set<String>, boundaries: Set<String>))?
    if let coverage {
        classify = { coverage.classify($0) }
    } else {
        classify = nil
    }
    return await runUnaryLaw(
        "Equatable.reflexivity",
        generator: generator,
        options: options,
        observation: PerLawDriver.Observation(classify: classify),
        property: { sample in sample == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x == x evaluated to false"
        }
    )
}

private func checkSymmetry<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Equatable.symmetry",
        generator: generator,
        options: options,
        property: { first, second in
            (first == second) == (second == first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x == y → \(first == second), y == x → \(second == first)"
        }
    )
}

private func checkTransitivity<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Equatable.transitivity",
        generator: generator,
        options: options,
        property: { first, second, third in
            !(first == second && second == third) || (first == third)
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x == y and y == z but x != z"
        }
    )
}

// Defensive coverage. `!=` is dispatched through Equatable's protocol witness
// as `!(lhs == rhs)`, so this law is structurally unviolable for any Value
// whose `==` is observed through generic dispatch. The check stays in case a
// future Swift change makes `!=` independently overridable; today it always
// passes.
private func checkNegationConsistency<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Equatable.negationConsistency",
        generator: generator,
        options: options,
        property: { first, second in
            (first != second) == !(first == second)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x != y → \(first != second), !(x == y) → \(!(first == second))"
        }
    )
}
