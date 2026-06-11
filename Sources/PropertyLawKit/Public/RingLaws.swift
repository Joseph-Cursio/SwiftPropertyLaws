import PropertyBased

/// Run `Ring` protocol laws over `Value` (PRD §4.3 v1.10 — kit-defined).
///
/// Eleven Strict-tier laws — a violation is a bug. `Ring` is **standalone**
/// (it refines nothing in the kit's algebraic DAG — see `Ring.swift` and the
/// `docs/Protocols/v1.10 plan.md` "Why standalone" section), so there is no
/// inherited-chain collection and no `laws:` selection parameter: the suite
/// always runs all eleven of its own laws.
///
/// Returned-array order — additive abelian group, then multiplicative
/// monoid, then distributivity:
/// `addAssociativity`, `addCommutativity`, `addLeftIdentity`,
/// `addRightIdentity`, `addLeftInverse`, `addRightInverse`,
/// `multiplyAssociativity`, `multiplyLeftIdentity`, `multiplyRightIdentity`,
/// `leftDistributivity`, `rightDistributivity` (all Strict).
///
/// **Generator caveat.** Associativity and distributivity are three-sample
/// laws; rings that grow under `multiply`/`add` (polynomials, free algebras)
/// multiply per-trial allocation. Prefer small-input generators (e.g. a
/// finite `Z/nZ` or bounded-degree polynomials) so the trial budget stays
/// bounded — same posture as the `Semigroup` associativity caveat.
@discardableResult
public func checkRingPropertyLaws<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkAddAssociativity(generator: generator, options: options),
        await checkAddCommutativity(generator: generator, options: options),
        await checkAddLeftIdentity(generator: generator, options: options),
        await checkAddRightIdentity(generator: generator, options: options),
        await checkAddLeftInverse(generator: generator, options: options),
        await checkAddRightInverse(generator: generator, options: options),
        await checkMultiplyAssociativity(generator: generator, options: options),
        await checkMultiplyLeftIdentity(generator: generator, options: options),
        await checkMultiplyRightIdentity(generator: generator, options: options),
        await checkLeftDistributivity(generator: generator, options: options),
        await checkRightDistributivity(generator: generator, options: options)
    ]
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

// MARK: - Additive abelian group

private func checkAddAssociativity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Ring.addAssociativity",
        generator: generator,
        options: options,
        property: { first, second, third in
            Value.add(Value.add(first, second), third)
                == Value.add(first, Value.add(second, third))
        },
        formatCounterexample: { first, second, third, _ in
            let lhs = Value.add(Value.add(first, second), third)
            let rhs = Value.add(first, Value.add(second, third))
            return "x = \(first), y = \(second), z = \(third); "
                + "add(add(x, y), z) = \(lhs), add(x, add(y, z)) = \(rhs)"
        }
    )
}

private func checkAddCommutativity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Ring.addCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            Value.add(first, second) == Value.add(second, first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "add(x, y) = \(Value.add(first, second)), "
                + "add(y, x) = \(Value.add(second, first))"
        }
    )
}

private func checkAddLeftIdentity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Ring.addLeftIdentity",
        generator: generator,
        options: options,
        property: { sample in Value.add(Value.zero, sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); add(.zero, x) = \(Value.add(Value.zero, sample)), expected x"
        }
    )
}

private func checkAddRightIdentity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Ring.addRightIdentity",
        generator: generator,
        options: options,
        property: { sample in Value.add(sample, Value.zero) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); add(x, .zero) = \(Value.add(sample, Value.zero)), expected x"
        }
    )
}

private func checkAddLeftInverse<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Ring.addLeftInverse",
        generator: generator,
        options: options,
        property: { sample in Value.add(Value.negate(sample), sample) == Value.zero },
        formatCounterexample: { sample, _ in
            "x = \(sample); add(negate(x), x) = "
                + "\(Value.add(Value.negate(sample), sample)), expected .zero"
        }
    )
}

private func checkAddRightInverse<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Ring.addRightInverse",
        generator: generator,
        options: options,
        property: { sample in Value.add(sample, Value.negate(sample)) == Value.zero },
        formatCounterexample: { sample, _ in
            "x = \(sample); add(x, negate(x)) = "
                + "\(Value.add(sample, Value.negate(sample))), expected .zero"
        }
    )
}

// MARK: - Multiplicative monoid

private func checkMultiplyAssociativity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Ring.multiplyAssociativity",
        generator: generator,
        options: options,
        property: { first, second, third in
            Value.multiply(Value.multiply(first, second), third)
                == Value.multiply(first, Value.multiply(second, third))
        },
        formatCounterexample: { first, second, third, _ in
            let lhs = Value.multiply(Value.multiply(first, second), third)
            let rhs = Value.multiply(first, Value.multiply(second, third))
            return "x = \(first), y = \(second), z = \(third); "
                + "multiply(multiply(x, y), z) = \(lhs), "
                + "multiply(x, multiply(y, z)) = \(rhs)"
        }
    )
}

private func checkMultiplyLeftIdentity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Ring.multiplyLeftIdentity",
        generator: generator,
        options: options,
        property: { sample in Value.multiply(Value.one, sample) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); multiply(.one, x) = "
                + "\(Value.multiply(Value.one, sample)), expected x"
        }
    )
}

private func checkMultiplyRightIdentity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Ring.multiplyRightIdentity",
        generator: generator,
        options: options,
        property: { sample in Value.multiply(sample, Value.one) == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); multiply(x, .one) = "
                + "\(Value.multiply(sample, Value.one)), expected x"
        }
    )
}

// MARK: - Distributivity (the cross-structure laws)

private func checkLeftDistributivity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Ring.leftDistributivity",
        generator: generator,
        options: options,
        property: { first, second, third in
            Value.multiply(first, Value.add(second, third))
                == Value.add(Value.multiply(first, second), Value.multiply(first, third))
        },
        formatCounterexample: { first, second, third, _ in
            let lhs = Value.multiply(first, Value.add(second, third))
            let rhs = Value.add(Value.multiply(first, second), Value.multiply(first, third))
            return "x = \(first), y = \(second), z = \(third); "
                + "multiply(x, add(y, z)) = \(lhs), "
                + "add(multiply(x, y), multiply(x, z)) = \(rhs)"
        }
    )
}

private func checkRightDistributivity<
    Value: Ring & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Ring.rightDistributivity",
        generator: generator,
        options: options,
        property: { first, second, third in
            Value.multiply(Value.add(first, second), third)
                == Value.add(Value.multiply(first, third), Value.multiply(second, third))
        },
        formatCounterexample: { first, second, third, _ in
            let lhs = Value.multiply(Value.add(first, second), third)
            let rhs = Value.add(Value.multiply(first, third), Value.multiply(second, third))
            return "x = \(first), y = \(second), z = \(third); "
                + "multiply(add(x, y), z) = \(lhs), "
                + "add(multiply(x, z), multiply(y, z)) = \(rhs)"
        }
    )
}
