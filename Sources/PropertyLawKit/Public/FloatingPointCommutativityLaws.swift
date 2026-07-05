import PropertyBased

// The runnable algebraic subset for IEEE-754 floating-point: additive and
// multiplicative commutativity. These are the *only* pieces of the inherited
// AdditiveArithmetic / Numeric chain that hold **exactly** over floats
// (bit-for-bit, modulo NaN): `a + b` and `b + a` — likewise `a * b` and
// `b * a` — produce the identical value. They run via `floatSameResult`
// (NaN-reflexive, no tolerance term) so a NaN on both sides reads as "same
// result" rather than a spurious counterexample. Associativity /
// distributivity / subtraction-inverse are deliberately *not* run — they fail
// by unbounded amounts under catastrophic cancellation, and no oracle rescues
// them. `checkFloatingPointPropertyLaws` appends both to its always-on set.

func checkAdditionCommutativityExact<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "FloatingPoint.additionCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            floatSameResult(first + second, second + first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x + y = \(first + second), y + x = \(second + first)"
        }
    )
}

func checkMultiplicationCommutativityExact<
    Value: FloatingPoint & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "FloatingPoint.multiplicationCommutativity",
        generator: generator,
        options: options,
        property: { first, second in
            floatSameResult(first * second, second * first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x * y = \(first * second), y * x = \(second * first)"
        }
    )
}
