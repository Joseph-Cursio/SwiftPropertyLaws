import PropertyBased

// swiftlint:disable file_length
// BinaryInteger carries 16 Strict-tier laws (division, bitwise, shift,
// bit-counting). One private check function per law per the kit's pattern
// drives the file past the default 400-line limit; splitting per-cluster
// would fragment what is conceptually a single suite.

/// Run `BinaryInteger` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Numeric` suite first (which
/// transitively runs `AdditiveArithmetic`'s) per PRD §4.3 inheritance
/// semantics; `.ownOnly` skips them.
///
/// Returned-array order: inherited laws first (when `.all`), then 16
/// BinaryInteger laws — five division/remainder, nine bitwise, one shift,
/// one bit-counting (`trailingZeroBitCountRange`) — all Strict.
/// `nonzeroBitCount` is FixedWidthInteger-only and lands in v1.4 M3.
///
/// **Generator caveat for FixedWidthInteger types.** Three-way multiplication
/// in the inherited Numeric laws overflows under unbounded sampling — pass a
/// magnitude-bounded generator (e.g. `Gen<Int>.boundedForArithmetic()`).
/// Bitwise and shift laws are safe at any range. Division laws skip samples
/// where the divisor is zero (vacuous-true), so a generator that produces
/// zeros costs trials but won't crash.
@discardableResult
public func checkBinaryIntegerPropertyLaws<
    Value: BinaryInteger & Sendable,
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
                try await checkNumericPropertyLaws(
                    for: type,
                    using: generator,
                    options: $0
                )
            })
        }
        results.append(contentsOf: [
            await checkDivisionMultiplicationRoundTrip(generator: generator, options: options),
            await checkRemainderMagnitudeBound(generator: generator, options: options),
            await checkSelfDivisionIsOne(generator: generator, options: options),
            await checkDivisionByOneIdentity(generator: generator, options: options),
            await checkQuotientAndRemainderConsistency(generator: generator, options: options),
            await checkBitwiseAndIdempotence(generator: generator, options: options),
            await checkBitwiseOrIdempotence(generator: generator, options: options),
            await checkBitwiseAndCommutativity(generator: generator, options: options),
            await checkBitwiseOrCommutativity(generator: generator, options: options),
            await checkBitwiseXorSelfIsZero(generator: generator, options: options),
            await checkBitwiseXorZeroIdentity(generator: generator, options: options),
            await checkBitwiseDoubleNegation(generator: generator, options: options),
            await checkBitwiseAndDistributesOverOr(generator: generator, options: options),
            await checkBitwiseDeMorgan(generator: generator, options: options),
            await checkShiftByZeroIdentity(generator: generator, options: options),
            await checkTrailingZeroBitCountRange(generator: generator, options: options)
        ])
        return results
    }
}

// MARK: - Division / remainder

private func checkDivisionMultiplicationRoundTrip<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "BinaryInteger.divisionMultiplicationRoundTrip",
        generator: generator,
        options: options,
        property: { numerator, denominator in
            guard denominator != 0 else { return true }
            return (numerator / denominator) * denominator + (numerator % denominator)
                == numerator
        },
        formatCounterexample: { numerator, denominator, _ in
            if denominator == 0 { return "denominator was zero (skipped)" }
            let lhs = (numerator / denominator) * denominator + (numerator % denominator)
            return "x = \(numerator), y = \(denominator); "
                + "(x / y) * y + (x % y) = \(lhs), expected x"
        }
    )
}

private func checkRemainderMagnitudeBound<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "BinaryInteger.remainderMagnitudeBound",
        generator: generator,
        options: options,
        property: { numerator, denominator in
            guard denominator != 0 else { return true }
            let remainder = numerator % denominator
            return remainder.magnitude < denominator.magnitude
                || remainder == 0
        },
        formatCounterexample: { numerator, denominator, _ in
            if denominator == 0 { return "denominator was zero (skipped)" }
            let remainder = numerator % denominator
            return "x = \(numerator), y = \(denominator); "
                + "x % y = \(remainder); |\(remainder)| ≮ |\(denominator)|"
        }
    )
}

private func checkSelfDivisionIsOne<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.selfDivisionIsOne",
        generator: generator,
        options: options,
        property: { sample in
            guard sample != 0 else { return true }
            return sample / sample == 1
        },
        formatCounterexample: { sample, _ in
            if sample == 0 { return "x was zero (skipped)" }
            return "x = \(sample); x / x = \(sample / sample), expected 1"
        }
    )
}

private func checkDivisionByOneIdentity<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.divisionByOneIdentity",
        generator: generator,
        options: options,
        property: { sample in sample / 1 == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x / 1 = \(sample / 1), expected x"
        }
    )
}

private func checkQuotientAndRemainderConsistency<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "BinaryInteger.quotientAndRemainderConsistency",
        generator: generator,
        options: options,
        property: { numerator, denominator in
            guard denominator != 0 else { return true }
            let pair = numerator.quotientAndRemainder(dividingBy: denominator)
            return pair.quotient == numerator / denominator
                && pair.remainder == numerator % denominator
        },
        formatCounterexample: { numerator, denominator, _ in
            if denominator == 0 { return "denominator was zero (skipped)" }
            let pair = numerator.quotientAndRemainder(dividingBy: denominator)
            return "x = \(numerator), y = \(denominator); "
                + "quotientAndRemainder = \(pair); "
                + "(x/y, x%y) = (\(numerator / denominator), \(numerator % denominator))"
        }
    )
}

// MARK: - Bitwise

private func checkBitwiseAndIdempotence<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.bitwiseAndIdempotence",
        generator: generator,
        options: options,
        property: { sample in (sample & sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x & x = \(sample & sample), expected x"
        }
    )
}

private func checkBitwiseOrIdempotence<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.bitwiseOrIdempotence",
        generator: generator,
        options: options,
        property: { sample in (sample | sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x | x = \(sample | sample), expected x"
        }
    )
}

private func checkBitwiseAndCommutativity<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "BinaryInteger.bitwiseAndCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            (first & second) == (second & first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x & y = \(first & second), y & x = \(second & first)"
        }
    )
}

private func checkBitwiseOrCommutativity<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "BinaryInteger.bitwiseOrCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            (first | second) == (second | first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x | y = \(first | second), y | x = \(second | first)"
        }
    )
}

private func checkBitwiseXorSelfIsZero<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.bitwiseXorSelfIsZero",
        generator: generator,
        options: options,
        property: { sample in (sample ^ sample) == 0 },
        formatCounterexample: { sample, _ in
            "x = \(sample); x ^ x = \(sample ^ sample), expected 0"
        }
    )
}

private func checkBitwiseXorZeroIdentity<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.bitwiseXorZeroIdentity",
        generator: generator,
        options: options,
        property: { sample in (sample ^ 0) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x ^ 0 = \(sample ^ 0), expected x"
        }
    )
}

private func checkBitwiseDoubleNegation<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.bitwiseDoubleNegation",
        generator: generator,
        options: options,
        property: { sample in ~(~sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); ~~x = \(~(~sample)), expected x"
        }
    )
}

private func checkBitwiseAndDistributesOverOr<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "BinaryInteger.bitwiseAndDistributesOverOr",
        generator: generator,
        options: options,
        property: { one, two, three in
            (one & (two | three)) == ((one & two) | (one & three))
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = one & (two | three)
            let rhs = (one & two) | (one & three)
            return "x = \(one), y = \(two), z = \(three); "
                + "x & (y | z) = \(lhs), (x & y) | (x & z) = \(rhs)"
        }
    )
}

private func checkBitwiseDeMorgan<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "BinaryInteger.bitwiseDeMorgan",
        generator: generator,
        options: options,
        property: { first, second in
            ~(first & second) == (~first | ~second)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "~(x & y) = \(~(first & second)), ~x | ~y = \(~first | ~second)"
        }
    )
}

// MARK: - Shift

private func checkShiftByZeroIdentity<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.shiftByZeroIdentity",
        generator: generator,
        options: options,
        property: { sample in (sample << 0) == sample && (sample >> 0) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x << 0 = \(sample << 0), x >> 0 = \(sample >> 0)"
        }
    )
}

// MARK: - Bit-counting

private func checkTrailingZeroBitCountRange<
    Value: BinaryInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "BinaryInteger.trailingZeroBitCountRange",
        generator: generator,
        options: options,
        property: { sample in
            let count = sample.trailingZeroBitCount
            return count >= 0 && count <= sample.bitWidth
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); trailingZeroBitCount = \(sample.trailingZeroBitCount), "
                + "bitWidth = \(sample.bitWidth)"
        }
    )
}

// swiftlint:enable file_length
