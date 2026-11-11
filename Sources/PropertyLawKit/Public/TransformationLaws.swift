import PropertyBased

/// Checks the closure-free transformation laws over values drawn from `generator`.
///
/// `sorted()` must be idempotent, non-decreasing and count-preserving, and `reversed()`
/// must be an involution. These are promises of standard-library methods rather than of a
/// conformance.
///
/// - Parameters:
///   - generator: The values to check the laws against.
///   - options: The budget, enforcement and suppressions for the run.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkTransformationPropertyLaws<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] where Value.Element: Comparable & Sendable {
    try await runPropertyLawSuite(options: options) {
        [
            await checkSortedIdempotence(generator: generator, options: options),
            await checkSortedIsNonDecreasing(generator: generator, options: options),
            await checkSortedPreservesCount(generator: generator, options: options),
            await checkReversedInvolution(generator: generator, options: options),
        ]
    }
}

private func checkSortedIdempotence<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Comparable & Sendable {
    await runUnaryLaw(
        "Transformation.sortedIdempotence",
        generator: generator,
        options: options,
        property: { sample in sample.sorted().sorted() == sample.sorted() },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); x.sorted().sorted() = \(sample.sorted().sorted()), "
                + "x.sorted() = \(sample.sorted())"
        }
    )
}

private func checkSortedIsNonDecreasing<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Comparable & Sendable {
    await runUnaryLaw(
        "Transformation.sortedIsNonDecreasing",
        generator: generator,
        options: options,
        property: { sample in
            let sorted = sample.sorted()
            return zip(sorted, sorted.dropFirst()).allSatisfy { $0 <= $1 }
        },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); x.sorted() = \(sample.sorted()) has an "
                + "out-of-order adjacent pair"
        }
    )
}

private func checkSortedPreservesCount<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Comparable & Sendable {
    await runUnaryLaw(
        "Transformation.sortedPreservesCount",
        generator: generator,
        options: options,
        property: { sample in sample.sorted().count == Array(sample).count },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)) (count \(Array(sample).count)); "
                + "x.sorted() has count \(sample.sorted().count)"
        }
    )
}

private func checkReversedInvolution<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Comparable & Sendable {
    await runUnaryLaw(
        "Transformation.reversedInvolution",
        generator: generator,
        options: options,
        property: { sample in
            let once: [Value.Element] = sample.reversed()
            return Array(once.reversed()) == Array(sample)
        },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); x.reversed().reversed() = "
                + "\(Array(sample.reversed().reversed()))"
        }
    )
}
