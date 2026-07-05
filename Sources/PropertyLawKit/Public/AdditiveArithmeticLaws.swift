import PropertyBased

/// Run `AdditiveArithmetic` protocol laws over `Value` (PRD §4.3).
///
/// Five Strict-tier algebraic laws — a violation under any of them is a bug:
/// - `additionAssociativity` — `(x + y) + z == x + (y + z)`
/// - `additionCommutativity` — `x + y == y + x`
/// - `zeroAdditiveIdentity` — `x + .zero == x`
/// - `subtractionInverse` — `(x + y) - y == x`
/// - `selfSubtractionIsZero` — `x - x == .zero`
///
/// `AdditiveArithmetic` refines `Equatable` in stdlib; the law signatures
/// require both. No inherited suite runs because `Equatable` is not
/// auto-recursed by other roots in the kit.
///
/// **Generator caveat for FixedWidthInteger types.** `Int.max + 1` traps;
/// the law functions trust the caller's generator to stay within a range
/// that does not overflow under three-way addition / subtraction. For `Int`
/// or `Int32`, pass a bounded generator like `Gen<Int>.int(in: -1_000...1_000)`
/// at `.standard` budget. Arbitrary-precision integer types need no bound.
///
/// **Not for IEEE-754 floating-point.** Associativity and the subtraction
/// inverse hold only approximately for `Float` / `Double` because addition
/// rounds. The laws above use exact `==` and will report violations on
/// floating-point inputs that are mathematically — but not bitwise — equal.
/// Use `checkFloatingPointPropertyLaws` (v1.4 M4) for IEEE-754 types; their
/// laws account for rounding via approximate-equality semantics.
///
/// **Oracle injection.** `sameResult` is the equivalence used to compare the two
/// sides of `additionCommutativity` only (the one law here that holds *exactly*
/// over floats). It defaults to `==`; pass `floatSameResult` to make it
/// `NaN`-reflexive when running commutativity over a `NaN`-inclusive
/// floating-point generator. The remaining laws (associativity, identity,
/// subtraction inverse, self-subtraction) still use exact `==` and remain unfit
/// for floats regardless of `sameResult` — associativity and the subtraction
/// inverse fail by unbounded amounts under cancellation, so no oracle rescues
/// them.
@discardableResult
public func checkAdditiveArithmeticPropertyLaws<
    Value: AdditiveArithmetic & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sameResult: @escaping SameResult<Value> = { $0 == $1 }
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkAdditionAssociativity(generator: generator, options: options),
            await checkAdditionCommutativity(
                generator: generator,
                options: options,
                sameResult: sameResult
            ),
            await checkZeroAdditiveIdentity(generator: generator, options: options),
            await checkSubtractionInverse(generator: generator, options: options),
            await checkSelfSubtractionIsZero(generator: generator, options: options)
        ]
    }
}

private func checkAdditionAssociativity<
    Value: AdditiveArithmetic & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "AdditiveArithmetic.additionAssociativity",
        generator: generator,
        options: options,
        property: { one, two, three in
            (one + two) + three == one + (two + three)
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = (one + two) + three
            let rhs = one + (two + three)
            return "x = \(one), y = \(two), z = \(three); "
                + "(x + y) + z = \(lhs), x + (y + z) = \(rhs)"
        }
    )
}

private func checkAdditionCommutativity<
    Value: AdditiveArithmetic & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    sameResult: @escaping SameResult<Value> = { $0 == $1 }
) async -> CheckResult {
    await runBinaryLaw(
        "AdditiveArithmetic.additionCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            sameResult(first + second, second + first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x + y = \(first + second), y + x = \(second + first)"
        }
    )
}

private func checkZeroAdditiveIdentity<
    Value: AdditiveArithmetic & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AdditiveArithmetic.zeroAdditiveIdentity",
        generator: generator,
        options: options,
        property: { sample in sample + .zero == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x + .zero = \(sample + .zero), expected x"
        }
    )
}

private func checkSubtractionInverse<
    Value: AdditiveArithmetic & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "AdditiveArithmetic.subtractionInverse",
        generator: generator,
        options: options,
        property: { first, second in
            (first + second) - second == first
        },
        formatCounterexample: { first, second, _ in
            let lhs = (first + second) - second
            return "x = \(first), y = \(second); "
                + "(x + y) - y = \(lhs), expected x = \(first)"
        }
    )
}

private func checkSelfSubtractionIsZero<
    Value: AdditiveArithmetic & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AdditiveArithmetic.selfSubtractionIsZero",
        generator: generator,
        options: options,
        property: { sample in sample - sample == .zero },
        formatCounterexample: { sample, _ in
            "x = \(sample); x - x = \(sample - sample), expected .zero"
        }
    )
}
