import PropertyBased

/// Run `SignedNumeric` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Numeric` suite first (which
/// transitively runs `AdditiveArithmetic`'s) per PRD §4.3 inheritance
/// semantics; `.ownOnly` skips them.
///
/// Returned-array order: inherited laws first (when `.all`), then the four
/// SignedNumeric laws — `negationInvolution`, `additiveInverse`,
/// `negationDistributesOverAddition`, `negateMutationConsistency` (all
/// Strict).
///
/// `Value.min` traps under negation for two's-complement signed integers
/// (`-Int.min` overflows). Bounded generators that exclude `Value.min`
/// avoid the trap; for `Int`, a range like `Int.min + 1 ... Int.max` or a
/// magnitude-bounded `±10_000` range works.
///
/// **Not for IEEE-754 floating-point.** The inherited `Numeric` and
/// `AdditiveArithmetic` laws fire spurious violations on `Float` / `Double`
/// because of rounding. Use `checkFloatingPointPropertyLaws` (v1.4 M4) for
/// IEEE-754 types instead.
@discardableResult
public func checkSignedNumericPropertyLaws<
    Value: SignedNumeric & Equatable & Sendable,
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
            await checkNegationInvolution(generator: generator, options: options),
            await checkAdditiveInverse(generator: generator, options: options),
            await checkNegationDistributesOverAddition(generator: generator, options: options),
            await checkNegateMutationConsistency(generator: generator, options: options)
        ])
        return results
    }
}

private func checkNegationInvolution<
    Value: SignedNumeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SignedNumeric.negationInvolution",
        generator: generator,
        options: options,
        property: { sample in -(-sample) == sample },
        formatCounterexample: { sample, _ in
            let doubled = -(-sample)
            return "x = \(sample); -(-x) = \(doubled), expected x"
        }
    )
}

private func checkAdditiveInverse<
    Value: SignedNumeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SignedNumeric.additiveInverse",
        generator: generator,
        options: options,
        property: { sample in sample + (-sample) == .zero },
        formatCounterexample: { sample, _ in
            let sum = sample + (-sample)
            return "x = \(sample); x + (-x) = \(sum), expected .zero"
        }
    )
}

private func checkNegationDistributesOverAddition<
    Value: SignedNumeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "SignedNumeric.negationDistributesOverAddition",
        generator: generator,
        options: options,
        property: { first, second in
            -(first + second) == (-first) + (-second)
        },
        formatCounterexample: { first, second, _ in
            let lhs = -(first + second)
            let rhs = (-first) + (-second)
            return "x = \(first), y = \(second); "
                + "-(x + y) = \(lhs), (-x) + (-y) = \(rhs)"
        }
    )
}

private func checkNegateMutationConsistency<
    Value: SignedNumeric & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SignedNumeric.negateMutationConsistency",
        generator: generator,
        options: options,
        property: { sample in
            var mutated = sample
            mutated.negate()
            return mutated == -sample
        },
        formatCounterexample: { sample, _ in
            var mutated = sample
            mutated.negate()
            return "x = \(sample); var y = x; y.negate() ⇒ y = \(mutated), "
                + "expected -x = \(-sample)"
        }
    )
}
