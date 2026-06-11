import PropertyBased

// FixedWidthInteger carries 9 Strict-tier laws (bit-width invariants,
// four reportingOverflow tuple-consistency laws, wrapping arithmetic,
// min/max bounds, byteSwapped involution, nonzeroBitCount range — the
// last deferred from M2 since it's FixedWidthInteger-only).

/// Run `FixedWidthInteger` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `BinaryInteger` suite first
/// (which transitively runs `Numeric` and `AdditiveArithmetic`) per PRD
/// §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: inherited laws first (when `.all`), then nine
/// FixedWidthInteger laws — `bitWidthMatchesType`, four reportingOverflow
/// consistency laws, `wrappingArithmeticDoesNotTrap`,
/// `minMaxBoundsAreReachable`, `byteSwappedInvolution`,
/// `nonzeroBitCountRange`.
///
/// FixedWidthInteger is orthogonal to SignedInteger and UnsignedInteger
/// in the protocol hierarchy — types like `Int32` conform to both
/// FixedWidthInteger and SignedInteger, types like `UInt` conform to both
/// FixedWidthInteger and UnsignedInteger. The discovery plugin emits
/// matching checks for both per PRD §4.3 most-specific dedupe semantics.
@discardableResult
public func checkFixedWidthIntegerPropertyLaws<
    Value: FixedWidthInteger & Sendable,
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
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
            try await checkBinaryIntegerPropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(contentsOf: [
        await checkBitWidthMatchesType(generator: generator, options: options),
        await checkAddingReportingOverflowConsistency(generator: generator, options: options),
        await checkSubtractingReportingOverflowConsistency(generator: generator, options: options),
        await checkMultipliedReportingOverflowConsistency(generator: generator, options: options),
        await checkDividedReportingOverflowOnDivByZero(generator: generator, options: options),
        await checkWrappingArithmeticDoesNotTrap(generator: generator, options: options),
        await checkMinMaxBoundsAreReachable(generator: generator, options: options),
        await checkByteSwappedInvolution(generator: generator, options: options),
        await checkNonzeroBitCountRange(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

// MARK: - Bit-width invariants

private func checkBitWidthMatchesType<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.bitWidthMatchesType",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.bitWidth == Value.bitWidth },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.bitWidth = \(sample.bitWidth), "
                    + "Self.bitWidth = \(Value.bitWidth)"
            }
        )
    )
}

// MARK: - reportingOverflow consistency

private func checkAddingReportingOverflowConsistency<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.addingReportingOverflowConsistency",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (lhs, rhs) = input
                let pair = lhs.addingReportingOverflow(rhs)
                return pair.partialValue == lhs &+ rhs
            },
            formatCounterexample: { input, _ in
                let (lhs, rhs) = input
                let pair = lhs.addingReportingOverflow(rhs)
                return "x = \(lhs), y = \(rhs); "
                    + "addingReportingOverflow.partialValue = \(pair.partialValue), "
                    + "x &+ y = \(lhs &+ rhs)"
            }
        )
    )
}

private func checkSubtractingReportingOverflowConsistency<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.subtractingReportingOverflowConsistency",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (lhs, rhs) = input
                let pair = lhs.subtractingReportingOverflow(rhs)
                return pair.partialValue == lhs &- rhs
            },
            formatCounterexample: { input, _ in
                let (lhs, rhs) = input
                let pair = lhs.subtractingReportingOverflow(rhs)
                return "x = \(lhs), y = \(rhs); "
                    + "subtractingReportingOverflow.partialValue = \(pair.partialValue), "
                    + "x &- y = \(lhs &- rhs)"
            }
        )
    )
}

private func checkMultipliedReportingOverflowConsistency<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.multipliedReportingOverflowConsistency",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (lhs, rhs) = input
                let pair = lhs.multipliedReportingOverflow(by: rhs)
                return pair.partialValue == lhs &* rhs
            },
            formatCounterexample: { input, _ in
                let (lhs, rhs) = input
                let pair = lhs.multipliedReportingOverflow(by: rhs)
                return "x = \(lhs), y = \(rhs); "
                    + "multipliedReportingOverflow.partialValue = \(pair.partialValue), "
                    + "x &* y = \(lhs &* rhs)"
            }
        )
    )
}

private func checkDividedReportingOverflowOnDivByZero<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.dividedReportingOverflowOnDivByZero",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                let pair = sample.dividedReportingOverflow(by: 0)
                return pair.overflow == true
            },
            formatCounterexample: { sample, _ in
                let pair = sample.dividedReportingOverflow(by: 0)
                return "x = \(sample); x.dividedReportingOverflow(by: 0) = \(pair); "
                    + "expected overflow == true"
            }
        )
    )
}

// MARK: - Wrapping arithmetic + bounds

private func checkWrappingArithmeticDoesNotTrap<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.wrappingArithmeticDoesNotTrap",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { input in
                let (lhs, rhs) = input
                _ = lhs &+ rhs
                _ = lhs &- rhs
                _ = lhs &* rhs
                return true
            },
            formatCounterexample: { input, _ in
                let (lhs, rhs) = input
                return "x = \(lhs), y = \(rhs); &+ &- &* should not trap"
            }
        )
    )
}

private func checkMinMaxBoundsAreReachable<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.minMaxBoundsAreReachable",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in Value.min <= sample && sample <= Value.max },
            formatCounterexample: { sample, _ in
                "x = \(sample); Value.min = \(Value.min), Value.max = \(Value.max); "
                    + "expected min <= x <= max"
            }
        )
    )
}

// MARK: - Byte swap

private func checkByteSwappedInvolution<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.byteSwappedInvolution",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.byteSwapped.byteSwapped == sample },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.byteSwapped.byteSwapped = "
                    + "\(sample.byteSwapped.byteSwapped), expected x"
            }
        )
    )
}

// MARK: - Bit count (FixedWidthInteger-only — deferred from M2)

private func checkNonzeroBitCountRange<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "FixedWidthInteger.nonzeroBitCountRange",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                let count = sample.nonzeroBitCount
                return count >= 0 && count <= sample.bitWidth
            },
            formatCounterexample: { sample, _ in
                "x = \(sample); nonzeroBitCount = \(sample.nonzeroBitCount), "
                    + "bitWidth = \(sample.bitWidth)"
            }
        )
    )
}
