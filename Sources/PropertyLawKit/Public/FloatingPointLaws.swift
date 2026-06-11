import PropertyBased

// FloatingPoint carries 9 always-on Strict laws + 5 NaN-domain laws gated
// on `LawCheckOptions.allowNaN`. The kit deliberately does NOT auto-run the
// inherited SignedNumeric / Numeric / AdditiveArithmetic chain — those are
// exact-equality algebraic laws that hold only approximately on IEEE-754
// floating-point types because of rounding. A type spelled `: FloatingPoint`
// emits only `checkFloatingPointPropertyLaws`; users wanting algebraic
// coverage on a finite-only generator opt in by calling the inherited check
// directly.

/// Run `FloatingPoint` protocol laws over `Value` (PRD §4.3).
///
/// FloatingPoint is the first kit protocol where the inherited chain is
/// deliberately not auto-run. AdditiveArithmetic / Numeric / SignedNumeric
/// laws use exact `==` and fire spurious violations on `Float` / `Double`
/// because IEEE-754 multiplication and addition round. The own-only
/// FloatingPoint laws below either avoid arithmetic comparison entirely
/// (`isFinite`, `isNaN`, `isInfinite`) or guard arithmetic chains behind
/// `isFinite` so rounding noise can't trigger a false positive.
///
/// **Always-on laws (9):** `infinityIsInfinite`, `negativeInfinityComparison`,
/// `zeroIsZero`, `signedZeroEquality`, `roundedZeroIdentity`,
/// `additiveInverseFinite`, `nextUpDownRoundTrip`, `signMatchesIsLessThanZero`,
/// `absoluteValueNonNegative`. NaN samples are skipped where they'd cause
/// IEEE-754-mandated false-arithmetic results.
///
/// **NaN-domain laws (5, gated by `options.allowNaN`):** `nanIsNaN`,
/// `nanInequality`, `nanPropagatesAddition`, `nanPropagatesMultiplication`,
/// `nanComparisonIsUnordered`. Each tests `Self.nan` directly — the
/// canonical qNaN. Signaling-NaN behavior is platform-specific and out of
/// scope.
///
/// Generators: pass `Gen<Double>.double(in: -1e6...1e6)` for finite-only
/// runs, or `Gen<Double>.doubleWithNaN()` if you want the always-on laws
/// to also exercise NaN-skip guards. The NaN-domain laws don't require the
/// generator to produce NaN — they construct it directly via `Self.nan`.
@discardableResult
public func checkFloatingPointPropertyLaws<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    var results: [CheckResult] = [
        await checkInfinityIsInfinite(type: type, options: options),
        await checkNegativeInfinityComparison(type: type, options: options),
        await checkZeroIsZero(type: type, options: options),
        await checkSignedZeroEquality(type: type, options: options),
        await checkRoundedZeroIdentity(type: type, options: options),
        await checkAdditiveInverseFinite(generator: generator, options: options),
        await checkNextUpDownRoundTrip(generator: generator, options: options),
        await checkSignMatchesIsLessThanZero(generator: generator, options: options),
        await checkAbsoluteValueNonNegative(generator: generator, options: options)
    ]
    if options.allowNaN {
        results.append(contentsOf: [
            await checkNaNIsNaN(type: type, options: options),
            await checkNaNInequality(type: type, options: options),
            await checkNaNPropagatesAddition(generator: generator, options: options),
            await checkNaNPropagatesMultiplication(generator: generator, options: options),
            await checkNaNComparisonIsUnordered(generator: generator, options: options)
        ])
    }
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

// MARK: - Always-on laws

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkInfinityIsInfinite<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.infinityIsInfinite",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in Value.infinity.isInfinite },
            formatCounterexample: { _, _ in
                "Value.infinity.isInfinite returned false"
            }
        )
    )
}

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkNegativeInfinityComparison<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.negativeInfinityComparison",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in -Value.infinity < Value.infinity },
            formatCounterexample: { _, _ in
                "expected -infinity < +infinity"
            }
        )
    )
}

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkZeroIsZero<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.zeroIsZero",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in Value.zero.isZero },
            formatCounterexample: { _, _ in
                "Value.zero.isZero returned false"
            }
        )
    )
}

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkSignedZeroEquality<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.signedZeroEquality",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in Value.zero == -Value.zero },
            formatCounterexample: { _, _ in
                "Value.zero == -Value.zero returned false (IEEE-754 mandates equality)"
            }
        )
    )
}

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkRoundedZeroIdentity<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.roundedZeroIdentity",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in Value.zero.rounded() == Value.zero },
            formatCounterexample: { _, _ in
                "Value.zero.rounded() != Value.zero"
            }
        )
    )
}

private func checkAdditiveInverseFinite<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.additiveInverseFinite",
        generator: generator,
        options: options,
        property: { sample in
            guard sample.isFinite else { return true }
            return sample + (-sample) == .zero
        },
        formatCounterexample: { sample, _ in
            if !sample.isFinite { return "x = \(sample) (non-finite, skipped)" }
            return "x = \(sample); x + (-x) = \(sample + (-sample)), expected .zero"
        }
    )
}

private func checkNextUpDownRoundTrip<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.nextUpDownRoundTrip",
        generator: generator,
        options: options,
        property: { sample in
            // Skip non-finite, the two extreme finite values, and -0
            // (whose nextDown is -leastNonzeroMagnitude — round-trip up
            // does not return to -0 but to +0 in some implementations).
            guard sample.isFinite,
                  sample != Value.greatestFiniteMagnitude,
                  sample != -Value.greatestFiniteMagnitude,
                  !sample.isZero
            else { return true }
            return sample.nextUp.nextDown == sample
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.nextUp.nextDown = \(sample.nextUp.nextDown), expected x"
        }
    )
}

private func checkSignMatchesIsLessThanZero<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.signMatchesIsLessThanZero",
        generator: generator,
        options: options,
        property: { sample in
            guard sample.isFinite, !sample.isZero else { return true }
            if sample < 0 { return sample.sign == .minus }
            return sample.sign == .plus
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.sign = \(sample.sign), x < 0 = \(sample < 0)"
        }
    )
}

private func checkAbsoluteValueNonNegative<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.absoluteValueNonNegative",
        generator: generator,
        options: options,
        property: { sample in
            guard !sample.isNaN else { return true }
            return sample.magnitude >= 0
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.magnitude = \(sample.magnitude), expected >= 0"
        }
    )
}

// MARK: - NaN-domain laws (gated by allowNaN)

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkNaNIsNaN<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.nanIsNaN",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in Value.nan.isNaN },
            formatCounterexample: { _, _ in
                "Value.nan.isNaN returned false"
            }
        )
    )
}

// Not eligible: samples a constant `0` rather than drawing from a generator.
private func checkNaNInequality<Value: FloatingPoint & Sendable>(
    type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FloatingPoint.nanInequality",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { _ in 0 },
            property: { _ in
                let leftNan = Value.nan
                let rightNan = Value.nan
                return leftNan != rightNan
            },
            formatCounterexample: { _, _ in
                "Value.nan == Value.nan returned true (IEEE-754 mandates inequality)"
            }
        )
    )
}

private func checkNaNPropagatesAddition<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.nanPropagatesAddition",
        generator: generator,
        options: options,
        property: { sample in (Value.nan + sample).isNaN },
        formatCounterexample: { sample, _ in
            "x = \(sample); (Value.nan + x) = \(Value.nan + sample), expected NaN"
        }
    )
}

private func checkNaNPropagatesMultiplication<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.nanPropagatesMultiplication",
        generator: generator,
        options: options,
        property: { sample in (Value.nan * sample).isNaN },
        formatCounterexample: { sample, _ in
            "x = \(sample); (Value.nan * x) = \(Value.nan * sample), expected NaN"
        }
    )
}

private func checkNaNComparisonIsUnordered<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FloatingPoint.nanComparisonIsUnordered",
        generator: generator,
        options: options,
        property: { sample in
            let nanValue = Value.nan
            return !(nanValue < sample) && !(nanValue > sample) && !(nanValue == sample)
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); NaN < x or NaN > x or NaN == x returned true"
        }
    )
}
