import PropertyBased

/// Run `BinaryFloatingPoint` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `FloatingPoint` suite first
/// (which is itself own-only — see `FloatingPointLaws.swift` for the
/// rationale on not auto-running the algebraic chain). `.ownOnly` skips
/// FloatingPoint's nine always-on plus five `allowNaN`-gated laws.
///
/// Returned-array order: inherited FloatingPoint laws first (when `.all`),
/// then four BinaryFloatingPoint laws — `radix2Constraint`,
/// `significandExponentReconstruction`, `binadeMembership`,
/// `convertingFromIntegerExactness` (all Strict).
@discardableResult
public func checkBinaryFloatingPointPropertyLaws<
    Value: BinaryFloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = []
    if laws == .all {
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) { rebased in
            // Forward allowNaN into the inherited FloatingPoint check; the standard
            // helper does not carry this field, so rebuild here to preserve behaviour.
            let withNaN = LawCheckOptions(
                budget: rebased.budget,
                enforcement: rebased.enforcement,
                seed: rebased.seed,
                suppressions: rebased.suppressions,
                backend: rebased.backend,
                allowNaN: options.allowNaN
            )
            return try await checkFloatingPointPropertyLaws(
                for: type,
                using: generator,
                options: withNaN
            )
        })
    }
    results.append(contentsOf: [
        await checkRadix2Constraint(type: type, options: options),
        await checkSignificandExponentReconstruction(generator: generator, options: options),
        await checkBinadeMembership(generator: generator, options: options),
        await checkConvertingFromIntegerExactness(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkRadix2Constraint<Value: BinaryFloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "BinaryFloatingPoint.radix2Constraint",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in Value.radix == 2 },
            formatCounterexample: { _, _ in
                "Value.radix = \(Value.radix), expected 2"
            }
        )
    )
}

private func checkSignificandExponentReconstruction<
    Value: BinaryFloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "BinaryFloatingPoint.significandExponentReconstruction",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                guard sample.isFinite, !sample.isZero else { return true }
                let reconstructed = Value(
                    sign: sample.sign,
                    exponent: sample.exponent,
                    significand: sample.significand
                )
                return reconstructed == sample
            },
            formatCounterexample: { sample, _ in
                let reconstructed = Value(
                    sign: sample.sign,
                    exponent: sample.exponent,
                    significand: sample.significand
                )
                return "x = \(sample); Value(sign:, exponent:, significand:) = "
                    + "\(reconstructed), expected x"
            }
        )
    )
}

private func checkBinadeMembership<
    Value: BinaryFloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "BinaryFloatingPoint.binadeMembership",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                guard sample.isFinite, !sample.isZero, !sample.isSubnormal else { return true }
                // `binade` carries the sign of the original value and is
                // the largest power of two ≤ |x| in magnitude. The next
                // binade up is `2 * |binade|` for normal floats. Both
                // bounds use magnitude so the law holds for negative
                // samples too.
                let absoluteBinade = sample.binade.magnitude
                let absoluteValue = sample.magnitude
                let nextBinade = absoluteBinade * 2
                return absoluteBinade <= absoluteValue && absoluteValue < nextBinade
            },
            formatCounterexample: { sample, _ in
                let absoluteBinade = sample.binade.magnitude
                return "x = \(sample); |binade| = \(absoluteBinade), |x| = \(sample.magnitude); "
                    + "expected |binade| <= |x| < 2·|binade|"
            }
        )
    )
}

private func checkConvertingFromIntegerExactness<
    Value: BinaryFloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    // The generator parameter is unused — this law samples small integers
    // from a fixed range to exercise the Self(exactly: Int) round-trip.
    _ = generator
    return await PerLawDriver.run(
        protocolLaw: "BinaryFloatingPoint.convertingFromIntegerExactness",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in Int.random(in: -1024...1024, using: &rng) },
            property: { source in
                guard let asValue = Value(exactly: source) else { return true }
                guard let roundTripped = Int(exactly: asValue) else { return false }
                return roundTripped == source
            },
            formatCounterexample: { source, _ in
                if let asValue = Value(exactly: source) {
                    let roundTripped = Int(exactly: asValue)
                    return "n = \(source); Value(exactly:) = \(asValue); "
                        + "Int(exactly:) = \(String(describing: roundTripped))"
                }
                return "n = \(source); Value(exactly:) returned nil (skipped)"
            }
        )
    )
}
