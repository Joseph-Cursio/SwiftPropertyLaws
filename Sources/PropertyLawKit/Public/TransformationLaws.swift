import PropertyBased

/// Transformation-algebra laws over `Sequence` values (Phase 2 of the
/// collections/async workplan) — the higher-order counterpart to the
/// conformance families: instead of checking what a *type* promises, these
/// check what the stdlib's transformation methods promise over that type.
///
/// Four closure-free Strict-tier laws (the closure-parameterized laws —
/// map fusion, map/filter commutation, lazy-vs-eager — ship separately and
/// take caller-supplied functions):
///
/// - `sortedIdempotence` — `x.sorted().sorted() == x.sorted()`
/// - `sortedIsNonDecreasing` — no adjacent pair of `x.sorted()` is
///   out of order
/// - `sortedPreservesCount` — sorting neither drops nor invents elements
/// - `reversedInvolution` — reversing twice restores the original element
///   order (the *value* transform; distinct from
///   `BidirectionalCollection.reverseTraversalConsistency`, which checks
///   index walking)
///
/// **Multi-pass assumption.** Each property iterates its sample more than
/// once, so carriers must be multi-pass (every `Collection` is). Don't run
/// this family over single-pass sequences.
///
/// **No planted violator, deliberately.** `sorted()`/`reversed()` are
/// protocol-extension methods — a conforming type can't override them, so
/// there is no substitutable "buggy conformance" to plant (the M3
/// collections families note the same gap for concrete types). What these
/// laws *can* catch is a broken `Comparable` element corrupting `sorted()`
/// — but a violator's broken `<` would corrupt the law's own oracle
/// identically, so detection is not guaranteed; the family's evidence base
/// is upstream archaeology (the swift-collections Pass 3 precedent), not
/// the planted-bug gate.
public enum TransformationLaw: String, Sendable, Hashable, CaseIterable {
    case sortedIdempotence
    case sortedIsNonDecreasing
    case sortedPreservesCount
    case reversedInvolution
}

extension LawIdentifier {
    public static func transformation(_ law: TransformationLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Transformation", lawName: law.rawValue)
    }
}

@discardableResult
public func checkTransformationPropertyLaws<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] where Value.Element: Comparable & Sendable {
    try await runPropertyLawSuite(options: options) {
        [
            await checkSortedIdempotence(generator: generator, options: options),
            await checkSortedIsNonDecreasing(generator: generator, options: options),
            await checkSortedPreservesCount(generator: generator, options: options),
            await checkReversedInvolution(generator: generator, options: options)
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
