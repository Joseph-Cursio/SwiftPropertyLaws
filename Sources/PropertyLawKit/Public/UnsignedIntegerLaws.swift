import PropertyBased

/// Run `UnsignedInteger` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `BinaryInteger` suite first
/// (which transitively runs `Numeric` and `AdditiveArithmetic`) per PRD §4.3
/// inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: inherited BinaryInteger → own.
///
/// `UnsignedInteger`'s two own laws — `nonNegative` and `magnitudeIsSelf` —
/// guard against custom conformers that lie about signedness or whose
/// `magnitude` typealias points somewhere non-trivial. For stdlib `UInt*`
/// types the laws hold by construction.
@discardableResult
public func checkUnsignedIntegerPropertyLaws<
    Value: UnsignedInteger & Sendable,
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
            await checkNonNegative(generator: generator, options: options),
            await checkMagnitudeIsSelf(generator: generator, options: options)
        ])
        return results
    }
}

private func checkNonNegative<
    Value: UnsignedInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "UnsignedInteger.nonNegative",
        generator: generator,
        options: options,
        // Compare against `Self.zero` (homogeneous) rather than the literal
        // `0`. `x >= 0` types the literal as `Int` and routes through the
        // sign-aware *heterogeneous* comparison, which is correct for any
        // honest unsigned type and so makes the law unfalsifiable. `x >= .zero`
        // exercises the type's own `Comparable` ordering — the ordering callers
        // actually rely on — so a type whose `<` misorders relative to zero is
        // caught.
        property: { sample in sample >= .zero },
        formatCounterexample: { sample, _ in
            "x = \(sample); x >= .zero returned false "
                + "(unsigned values must order at or above zero)"
        }
    )
}

private func checkMagnitudeIsSelf<
    Value: UnsignedInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "UnsignedInteger.magnitudeIsSelf",
        generator: generator,
        options: options,
        property: { sample in sample.magnitude == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.magnitude = \(sample.magnitude), expected \(sample)"
        }
    )
}
