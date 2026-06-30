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
    try await runPropertyLawSuite(options: options) {
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
        return results
    }
}

// MARK: - Bit-width invariants

private func checkBitWidthMatchesType<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FixedWidthInteger.bitWidthMatchesType",
        generator: generator,
        options: options,
        property: { sample in sample.bitWidth == Value.bitWidth },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.bitWidth = \(sample.bitWidth), "
                + "Self.bitWidth = \(Value.bitWidth)"
        }
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
    await runBinaryLaw(
        "FixedWidthInteger.addingReportingOverflowConsistency",
        generator: generator,
        options: options,
        // Comparing `partialValue` against `lhs &+ rhs` is tautological — the
        // masking `&+` is *defined* generically as `addingReportingOverflow`'s
        // partial value. These checks are independent of `&+`: adding zero is
        // exact and never overflows, and a wrapping add followed by a wrapping
        // subtract of the same operand round-trips in two's complement.
        property: { lhs, rhs in
            let identity = lhs.addingReportingOverflow(0)
            let (sum, _) = lhs.addingReportingOverflow(rhs)
            let recovered = sum.subtractingReportingOverflow(rhs).partialValue
            return identity.partialValue == lhs
                && identity.overflow == false
                && recovered == lhs
        },
        formatCounterexample: { lhs, rhs, _ in
            let identity = lhs.addingReportingOverflow(0)
            let (sum, _) = lhs.addingReportingOverflow(rhs)
            let recovered = sum.subtractingReportingOverflow(rhs).partialValue
            return "x = \(lhs), y = \(rhs); "
                + "x.addingReportingOverflow(0) = \(identity), expected (\(lhs), false); "
                + "(x &+ y) &- y = \(recovered), expected x"
        }
    )
}

private func checkSubtractingReportingOverflowConsistency<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "FixedWidthInteger.subtractingReportingOverflowConsistency",
        generator: generator,
        options: options,
        // Independent of the masking `&-` (which is defined via this method):
        // subtracting zero is the identity, subtracting self yields zero, and
        // a wrapping subtract followed by a wrapping add round-trips.
        property: { lhs, rhs in
            let identity = lhs.subtractingReportingOverflow(0)
            let selfDiff = lhs.subtractingReportingOverflow(lhs)
            let (diff, _) = lhs.subtractingReportingOverflow(rhs)
            let recovered = diff.addingReportingOverflow(rhs).partialValue
            return identity.partialValue == lhs && identity.overflow == false
                && selfDiff.partialValue == 0 && selfDiff.overflow == false
                && recovered == lhs
        },
        formatCounterexample: { lhs, rhs, _ in
            let identity = lhs.subtractingReportingOverflow(0)
            let selfDiff = lhs.subtractingReportingOverflow(lhs)
            let recovered = lhs.subtractingReportingOverflow(rhs)
                .partialValue.addingReportingOverflow(rhs).partialValue
            return "x = \(lhs), y = \(rhs); "
                + "x.subtractingReportingOverflow(0) = \(identity), expected (\(lhs), false); "
                + "x.subtractingReportingOverflow(x) = \(selfDiff), expected (0, false); "
                + "(x &- y) &+ y = \(recovered), expected x"
        }
    )
}

private func checkMultipliedReportingOverflowConsistency<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "FixedWidthInteger.multipliedReportingOverflowConsistency",
        generator: generator,
        options: options,
        // Independent of the masking `&*` (which is defined via this method):
        // multiplying by one is the identity (no overflow), multiplying by
        // zero is zero (no overflow), and the wrapping product commutes.
        property: { lhs, rhs in
            let byOne = lhs.multipliedReportingOverflow(by: 1)
            let byZero = lhs.multipliedReportingOverflow(by: 0)
            let (product, _) = lhs.multipliedReportingOverflow(by: rhs)
            let commuted = rhs.multipliedReportingOverflow(by: lhs).partialValue
            return byOne.partialValue == lhs && byOne.overflow == false
                && byZero.partialValue == 0 && byZero.overflow == false
                && product == commuted
        },
        formatCounterexample: { lhs, rhs, _ in
            let byOne = lhs.multipliedReportingOverflow(by: 1)
            let byZero = lhs.multipliedReportingOverflow(by: 0)
            let product = lhs.multipliedReportingOverflow(by: rhs).partialValue
            let commuted = rhs.multipliedReportingOverflow(by: lhs).partialValue
            return "x = \(lhs), y = \(rhs); "
                + "x.multipliedReportingOverflow(by: 1) = \(byOne), expected (\(lhs), false); "
                + "x.multipliedReportingOverflow(by: 0) = \(byZero), expected (0, false); "
                + "x &* y = \(product), y &* x = \(commuted)"
        }
    )
}

private func checkDividedReportingOverflowOnDivByZero<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FixedWidthInteger.dividedReportingOverflowOnDivByZero",
        generator: generator,
        options: options,
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
}

// MARK: - Wrapping arithmetic + bounds

private func checkWrappingArithmeticDoesNotTrap<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "FixedWidthInteger.wrappingArithmeticDoesNotTrap",
        generator: generator,
        options: options,
        // Executing `&+ &- &*` proves they do not trap; additionally the
        // wrap-around must land on the opposite boundary (`max &+ 1 == min`,
        // `min &- 1 == max` — true for both signed and unsigned two's
        // complement) and `&+` / `&-` must round-trip. An unconditional
        // `return true` here would be unfalsifiable.
        property: { lhs, rhs in
            _ = lhs &* rhs
            let roundTrip = (lhs &+ rhs) &- rhs
            return Value.max &+ 1 == Value.min
                && Value.min &- 1 == Value.max
                && roundTrip == lhs
        },
        formatCounterexample: { lhs, rhs, _ in
            "x = \(lhs), y = \(rhs); "
                + "Value.max &+ 1 = \(Value.max &+ 1), expected \(Value.min); "
                + "Value.min &- 1 = \(Value.min &- 1), expected \(Value.max); "
                + "(x &+ y) &- y = \((lhs &+ rhs) &- rhs), expected x"
        }
    )
}

private func checkMinMaxBoundsAreReachable<
    Value: FixedWidthInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "FixedWidthInteger.minMaxBoundsAreReachable",
        generator: generator,
        options: options,
        property: { sample in Value.min <= sample && sample <= Value.max },
        formatCounterexample: { sample, _ in
            "x = \(sample); Value.min = \(Value.min), Value.max = \(Value.max); "
                + "expected min <= x <= max"
        }
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
    await runUnaryLaw(
        "FixedWidthInteger.byteSwappedInvolution",
        generator: generator,
        options: options,
        property: { sample in sample.byteSwapped.byteSwapped == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.byteSwapped.byteSwapped = "
                + "\(sample.byteSwapped.byteSwapped), expected x"
        }
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
    await runUnaryLaw(
        "FixedWidthInteger.nonzeroBitCountRange",
        generator: generator,
        options: options,
        property: { sample in
            let count = sample.nonzeroBitCount
            return count >= 0 && count <= sample.bitWidth
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); nonzeroBitCount = \(sample.nonzeroBitCount), "
                + "bitWidth = \(sample.bitWidth)"
        }
    )
}
