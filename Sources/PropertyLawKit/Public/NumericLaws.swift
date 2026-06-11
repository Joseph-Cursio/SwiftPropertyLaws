import PropertyBased

/// Run `Numeric` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `AdditiveArithmetic` suite first
/// per PRD §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: inherited laws first (when `.all`), then the six
/// Numeric laws — `multiplicationAssociativity`, `multiplicationCommutativity`,
/// `oneMultiplicativeIdentity`, `zeroAnnihilation`, `leftDistributivity`,
/// `rightDistributivity` (all Strict).
///
/// **Generator caveat for FixedWidthInteger types.** Three-way multiplication
/// (`x * y * z`) overflows under unbounded random sampling on `Int`/`Int32`.
/// Pass a bounded generator (≈ ±cube-root of `T.max`) for fixed-width types
/// at `.standard` budget — e.g. `Gen<Int>.int(in: -1_000...1_000)`. The M2
/// milestone will ship a `Gen<T: FixedWidthInteger>.boundedForArithmetic()`
/// convenience helper.
///
/// **Not for IEEE-754 floating-point.** Associativity and distributivity
/// hold only approximately for `Float` / `Double` because multiplication and
/// addition round. The laws above use exact `==` and will fire spurious
/// violations on floating-point inputs. Use `checkFloatingPointPropertyLaws`
/// (v1.4 M4) for IEEE-754 types instead.
@discardableResult
public func checkNumericPropertyLaws<
    Value: Numeric & Equatable & Sendable,
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
            try await checkAdditiveArithmeticPropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(contentsOf: [
        await checkMultiplicationAssociativity(generator: generator, options: options),
        await checkMultiplicationCommutativity(generator: generator, options: options),
        await checkOneMultiplicativeIdentity(generator: generator, options: options),
        await checkZeroAnnihilation(generator: generator, options: options),
        await checkLeftDistributivity(generator: generator, options: options),
        await checkRightDistributivity(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkMultiplicationAssociativity<
    Value: Numeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Numeric.multiplicationAssociativity",
        generator: generator,
        options: options,
        property: { one, two, three in
            (one * two) * three == one * (two * three)
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = (one * two) * three
            let rhs = one * (two * three)
            return "x = \(one), y = \(two), z = \(three); "
                + "(x * y) * z = \(lhs), x * (y * z) = \(rhs)"
        }
    )
}

private func checkMultiplicationCommutativity<
    Value: Numeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Numeric.multiplicationCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            first * second == second * first
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x * y = \(first * second), y * x = \(second * first)"
        }
    )
}

private func checkOneMultiplicativeIdentity<
    Value: Numeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Numeric.oneMultiplicativeIdentity",
        generator: generator,
        options: options,
        property: { sample in sample * 1 == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x * 1 = \(sample * 1), expected x"
        }
    )
}

private func checkZeroAnnihilation<
    Value: Numeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Numeric.zeroAnnihilation",
        generator: generator,
        options: options,
        property: { sample in sample * 0 == .zero },
        formatCounterexample: { sample, _ in
            "x = \(sample); x * 0 = \(sample * 0), expected .zero"
        }
    )
}

private func checkLeftDistributivity<
    Value: Numeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Numeric.leftDistributivity",
        generator: generator,
        options: options,
        property: { one, two, three in
            one * (two + three) == one * two + one * three
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = one * (two + three)
            let rhs = one * two + one * three
            return "x = \(one), y = \(two), z = \(three); "
                + "x * (y + z) = \(lhs), x*y + x*z = \(rhs)"
        }
    )
}

private func checkRightDistributivity<
    Value: Numeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Numeric.rightDistributivity",
        generator: generator,
        options: options,
        property: { one, two, three in
            (one + two) * three == one * three + two * three
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = (one + two) * three
            let rhs = one * three + two * three
            return "x = \(one), y = \(two), z = \(three); "
                + "(x + y) * z = \(lhs), x*z + y*z = \(rhs)"
        }
    )
}
