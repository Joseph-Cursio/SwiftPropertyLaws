import PropertyBased

/// Run `SetAlgebra` protocol laws over `Value` (PRD §4.3).
///
/// Nine Strict-tier laws — a violation under any of them is a bug:
/// - `unionIdempotence` — `x.union(x) == x`
/// - `intersectionIdempotence` — `x.intersection(x) == x`
/// - `unionCommutativity` — `x.union(y) == y.union(x)`
/// - `intersectionCommutativity` — `x.intersection(y) == y.intersection(x)`
/// - `emptyIdentity` — `x.union(Self()) == x` (the protocol's `init()`
///   produces the empty set)
/// - `symmetricDifferenceSelfIsEmpty` — `x.symmetricDifference(x) == Self()`
/// - `symmetricDifferenceEmptyIdentity` — `x.symmetricDifference(Self()) == x`
/// - `symmetricDifferenceCommutativity` — `x.symmetricDifference(y) == y.symmetricDifference(x)`
/// - `symmetricDifferenceDefinition` — `x.symmetricDifference(y) ==
///   x.union(y).subtracting(x.intersection(y))`
///
/// The four `symmetricDifference*` laws closed a real-world gap: pre-fix
/// `swift-collections@35349601`, `TreeSet.symmetricDifference` returned the
/// intersection rather than the symmetric difference. With only the original
/// five laws, none of the kit's checks caught it. See `Validation/Pass3` for
/// the retroactive validation harness.
///
/// `SetAlgebra` does not formally extend `Equatable`, but in practice every
/// stdlib SetAlgebra type is `Equatable` and the laws above compare
/// `Self == Self`. The signature requires `Equatable` rather than threading
/// a caller-supplied predicate.
@discardableResult
public func checkSetAlgebraPropertyLaws<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkUnionIdempotence(generator: generator, options: options),
        await checkIntersectionIdempotence(generator: generator, options: options),
        await checkUnionCommutativity(generator: generator, options: options),
        await checkIntersectionCommutativity(generator: generator, options: options),
        await checkEmptyIdentity(generator: generator, options: options),
        await checkSymmetricDifferenceSelfIsEmpty(generator: generator, options: options),
        await checkSymmetricDifferenceEmptyIdentity(generator: generator, options: options),
        await checkSymmetricDifferenceCommutativity(generator: generator, options: options),
        await checkSymmetricDifferenceDefinition(generator: generator, options: options)
    ]
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkUnionIdempotence<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SetAlgebra.unionIdempotence",
        generator: generator,
        options: options,
        property: { sample in sample.union(sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.union(x) = \(sample.union(sample)), expected \(sample)"
        }
    )
}

private func checkIntersectionIdempotence<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SetAlgebra.intersectionIdempotence",
        generator: generator,
        options: options,
        property: { sample in sample.intersection(sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.intersection(x) = \(sample.intersection(sample)), "
                + "expected \(sample)"
        }
    )
}

private func checkUnionCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SetAlgebra.unionCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            first.union(second) == second.union(first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); x.union(y) = \(first.union(second)), "
                + "y.union(x) = \(second.union(first))"
        }
    )
}

private func checkIntersectionCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SetAlgebra.intersectionCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            first.intersection(second) == second.intersection(first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x.intersection(y) = \(first.intersection(second)), "
                + "y.intersection(x) = \(second.intersection(first))"
        }
    )
}

private func checkEmptyIdentity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SetAlgebra.emptyIdentity",
        generator: generator,
        options: options,
        property: { sample in sample.union(Value()) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.union(Self()) = \(sample.union(Value())), expected \(sample)"
        }
    )
}

private func checkSymmetricDifferenceSelfIsEmpty<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SetAlgebra.symmetricDifferenceSelfIsEmpty",
        generator: generator,
        options: options,
        property: { sample in sample.symmetricDifference(sample) == Value() },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.symmetricDifference(x) = "
                + "\(sample.symmetricDifference(sample)), expected \(Value())"
        }
    )
}

private func checkSymmetricDifferenceEmptyIdentity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SetAlgebra.symmetricDifferenceEmptyIdentity",
        generator: generator,
        options: options,
        property: { sample in sample.symmetricDifference(Value()) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.symmetricDifference(Self()) = "
                + "\(sample.symmetricDifference(Value())), expected \(sample)"
        }
    )
}

private func checkSymmetricDifferenceCommutativity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SetAlgebra.symmetricDifferenceCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            first.symmetricDifference(second) == second.symmetricDifference(first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x.symmetricDifference(y) = \(first.symmetricDifference(second)), "
                + "y.symmetricDifference(x) = \(second.symmetricDifference(first))"
        }
    )
}

private func checkSymmetricDifferenceDefinition<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SetAlgebra.symmetricDifferenceDefinition",
        generator: generator,
        options: options,
        property: { first, second in
            let viaSymDiff = first.symmetricDifference(second)
            let viaDefinition = first.union(second).subtracting(first.intersection(second))
            return viaSymDiff == viaDefinition
        },
        formatCounterexample: { first, second, _ in
            let viaSymDiff = first.symmetricDifference(second)
            let viaDefinition = first.union(second).subtracting(first.intersection(second))
            return "x = \(first), y = \(second); "
                + "x.symmetricDifference(y) = \(viaSymDiff), "
                + "(x ∪ y) \\ (x ∩ y) = \(viaDefinition)"
        }
    )
}
