import PropertyBased

/// Run `Hashable` protocol laws over `Value` (PRD §4.3).
///
/// By default (`laws: .all`), the inherited `Equatable` suite runs first per
/// PRD §4.3 inheritance semantics. Pass `laws: .ownOnly` to skip Equatable.
///
/// Returned array order: Equatable laws (if `.all`) then Hashable laws —
/// `equalityConsistency` (Strict), `stabilityWithinProcess` (Conventional),
/// `distribution` (Heuristic).
///
/// **Coverage hints (M5).** Optional `coverage:` classifier populates
/// `CheckResult.coverageHints` on `Hashable.stabilityWithinProcess` and
/// `Hashable.distribution` (the unary-input laws). The pair-input
/// `equalityConsistency` law silently ignores the classifier. When `.all`
/// is set, the inherited Equatable suite also receives the classifier.
@discardableResult
public func checkHashablePropertyLaws<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all,
    coverage: AnyCoverageClassifier<Value>? = nil
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkEquatablePropertyLaws(
                    for: type,
                    using: generator,
                    options: $0,
                    coverage: coverage
                )
            })
        }
        results.append(contentsOf: [
            await checkEqualityConsistency(generator: generator, options: options),
            await checkStabilityWithinProcess(generator: generator, options: options, coverage: coverage),
            await checkDistribution(generator: generator, options: options, coverage: coverage)
        ])
        return results
    }
}

private func checkEqualityConsistency<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Hashable.equalityConsistency",
        generator: generator,
        options: options,
        property: { first, second in
            !(first == second) || (first.hashValue == second.hashValue)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); x == y but hashValues differ "
                + "(\(first.hashValue) vs \(second.hashValue))"
        }
    )
}

private func checkStabilityWithinProcess<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
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
        "Hashable.stabilityWithinProcess",
        tier: .conventional,
        generator: generator,
        options: options,
        observation: PerLawDriver.Observation(classify: classify),
        property: { sample in sample.hashValue == sample.hashValue },
        formatCounterexample: { sample, _ in
            "x = \(sample); hashValue returned \(sample.hashValue) "
                + "then \(sample.hashValue) within the same process"
        }
    )
}

// Threshold of 0.10: a generator producing fewer than 10% unique hashes across
// the trial budget signals a degenerate distribution. The ratio matches the
// PRD §4.6 "hash distribution sanity" intent without claiming statistical
// rigor — this is Heuristic tier. Aggregate-mode (kit-side loop): the
// PropertyBackend protocol intentionally doesn't model whole-budget laws.
private func checkDistribution<Value: Hashable & Sendable, Shrinker: SendableSequenceType>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    coverage: AnyCoverageClassifier<Value>?
) async -> CheckResult {
    let accumulator: CoverageAccumulator? = coverage == nil ? nil : CoverageAccumulator()
    return await AggregateDriver.run(
        protocolLaw: "Hashable.distribution",
        tier: .heuristic,
        options: options,
        observation: AggregateDriver.Observation(coverageAccumulator: accumulator)
    ) { rng, count in
        var hashes = Set<Int>()
        var lastSample: Value?
        for _ in 0..<count {
            let sample = generator.run(using: &rng)
            lastSample = sample
            hashes.insert(sample.hashValue)
            if let coverage, let accumulator {
                let buckets = coverage.classify(sample)
                accumulator.record(classes: buckets.classes, boundaries: buckets.boundaries)
            }
        }
        let denominator = max(count, 1)
        let uniqueRatio = Double(hashes.count) / Double(denominator)
        if uniqueRatio < 0.10 {
            let sampleStr = lastSample.map { "\($0)" } ?? "<no samples>"
            let ratioStr = String(format: "%.3f", uniqueRatio)
            return .failed(counterexample:
                "\(count) samples produced only \(hashes.count) unique "
                    + "hashValues (ratio \(ratioStr)); last sample: \(sampleStr)"
            )
        }
        return .passed
    }
}
