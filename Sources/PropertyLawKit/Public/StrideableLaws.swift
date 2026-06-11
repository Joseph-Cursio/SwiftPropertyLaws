import PropertyBased

/// Run `Strideable` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Comparable` suite first (which
/// in turn runs `Equatable`'s) per PRD §4.3 inheritance semantics; `.ownOnly`
/// skips them.
///
/// Returned-array order: inherited laws first (when `.all`), then the four
/// Strideable laws — `distanceRoundTrip`, `advanceRoundTrip`,
/// `zeroAdvanceIdentity`, `selfDistanceIsZero` (all Strict).
///
/// Two generators are required because `Value.Stride` is an associated
/// type. For numeric types where `Stride == Self` (Int, Double, etc.) the
/// caller can pass the same shape twice; for types like `Date` where
/// `Stride == TimeInterval`, the stride generator must produce stride
/// values directly.
@discardableResult
public func checkStrideablePropertyLaws<
    Value: Strideable & Sendable,
    ValueShrinker: SendableSequenceType,
    StrideShrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, ValueShrinker>,
    strideGenerator: Generator<Value.Stride, StrideShrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] where Value.Stride: Sendable {
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
            try await checkComparablePropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(contentsOf: [
        await checkDistanceRoundTrip(
            generator: generator,
            strideGenerator: strideGenerator,
            options: options
        ),
        await checkAdvanceRoundTrip(
            generator: generator,
            strideGenerator: strideGenerator,
            options: options
        ),
        await checkZeroAdvanceIdentity(generator: generator, options: options),
        await checkSelfDistanceIsZero(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkDistanceRoundTrip<
    Value: Strideable & Sendable,
    ValueShrinker: SendableSequenceType,
    StrideShrinker: SendableSequenceType
>(
    generator: Generator<Value, ValueShrinker>,
    strideGenerator: Generator<Value.Stride, StrideShrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.Stride: Sendable {
    // `strideGenerator` is unused here but kept in the signature for
    // symmetry with checkAdvanceRoundTrip — silences the unused warning.
    _ = strideGenerator
    return await PerLawDriver.run(
        protocolLaw: "Strideable.distanceRoundTrip",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (first, second) = input
                return first.advanced(by: first.distance(to: second)) == second
            },
            formatCounterexample: { input, _ in
                let (first, second) = input
                let step = first.distance(to: second)
                let round = first.advanced(by: step)
                return "x = \(first), y = \(second); "
                    + "x.advanced(by: x.distance(to: y)) = \(round), expected y = \(second)"
            }
        )
    )
}

private func checkAdvanceRoundTrip<
    Value: Strideable & Sendable,
    ValueShrinker: SendableSequenceType,
    StrideShrinker: SendableSequenceType
>(
    generator: Generator<Value, ValueShrinker>,
    strideGenerator: Generator<Value.Stride, StrideShrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.Stride: Sendable {
    await PerLawDriver.run(
        protocolLaw: "Strideable.advanceRoundTrip",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), strideGenerator.run(using: &rng)) },
            property: { input in
                let (start, step) = input
                return start.distance(to: start.advanced(by: step)) == step
            },
            formatCounterexample: { input, _ in
                let (start, step) = input
                let advanced = start.advanced(by: step)
                let measured = start.distance(to: advanced)
                return "x = \(start), n = \(step); "
                    + "x.distance(to: x.advanced(by: n)) = \(measured), expected n = \(step)"
            }
        )
    )
}

private func checkZeroAdvanceIdentity<
    Value: Strideable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Strideable.zeroAdvanceIdentity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.advanced(by: .zero) == sample },
            formatCounterexample: { sample, _ in
                let advanced = sample.advanced(by: .zero)
                return "x = \(sample); x.advanced(by: .zero) = \(advanced), expected x"
            }
        )
    )
}

private func checkSelfDistanceIsZero<
    Value: Strideable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "Strideable.selfDistanceIsZero",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.distance(to: sample) == .zero },
            formatCounterexample: { sample, _ in
                let measured = sample.distance(to: sample)
                return "x = \(sample); x.distance(to: x) = \(measured), expected .zero"
            }
        )
    )
}
