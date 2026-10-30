import PropertyBased

// The six SetAlgebra laws relating `union`, `intersection` and `subtracting`
// to one another: distributivity, absorption and De Morgan. They run as part
// of `checkSetAlgebraPropertyLaws`, whose doc comment says why they were
// added. They live apart from it only to keep `SetAlgebraLaws.swift` within
// the file-length limit, which is why they are internal rather than private.

func checkUnionDistributivity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "SetAlgebra.unionDistributivity",
        generator: generator,
        options: options,
        property: { first, second, third in
            first.union(second.intersection(third))
                == first.union(second).intersection(first.union(third))
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x ∪ (y ∩ z) = \(first.union(second.intersection(third))), "
                + "(x ∪ y) ∩ (x ∪ z) = \(first.union(second).intersection(first.union(third)))"
        }
    )
}

func checkIntersectionDistributivity<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "SetAlgebra.intersectionDistributivity",
        generator: generator,
        options: options,
        property: { first, second, third in
            first.intersection(second.union(third))
                == first.intersection(second).union(first.intersection(third))
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x ∩ (y ∪ z) = \(first.intersection(second.union(third))), "
                + "(x ∩ y) ∪ (x ∩ z) = \(first.intersection(second).union(first.intersection(third)))"
        }
    )
}

func checkUnionAbsorption<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SetAlgebra.unionAbsorption",
        generator: generator,
        options: options,
        property: { first, second in
            first.union(first.intersection(second)) == first
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x ∪ (x ∩ y) = \(first.union(first.intersection(second))), expected \(first)"
        }
    )
}

func checkIntersectionAbsorption<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SetAlgebra.intersectionAbsorption",
        generator: generator,
        options: options,
        property: { first, second in
            first.intersection(first.union(second)) == first
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x ∩ (x ∪ y) = \(first.intersection(first.union(second))), expected \(first)"
        }
    )
}

func checkDeMorganForUnion<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "SetAlgebra.deMorganForUnion",
        generator: generator,
        options: options,
        property: { first, second, third in
            first.subtracting(second.union(third))
                == first.subtracting(second).intersection(first.subtracting(third))
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x \\ (y ∪ z) = \(first.subtracting(second.union(third))), "
                + "(x \\ y) ∩ (x \\ z) = "
                + "\(first.subtracting(second).intersection(first.subtracting(third)))"
        }
    )
}

func checkDeMorganForIntersection<
    Value: SetAlgebra & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "SetAlgebra.deMorganForIntersection",
        generator: generator,
        options: options,
        property: { first, second, third in
            first.subtracting(second.intersection(third))
                == first.subtracting(second).union(first.subtracting(third))
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x \\ (y ∩ z) = \(first.subtracting(second.intersection(third))), "
                + "(x \\ y) ∪ (x \\ z) = "
                + "\(first.subtracting(second).union(first.subtracting(third)))"
        }
    )
}
