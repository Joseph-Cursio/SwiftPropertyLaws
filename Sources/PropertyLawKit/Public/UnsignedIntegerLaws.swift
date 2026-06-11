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
        await checkNonNegative(generator: generator, options: options),
        await checkMagnitudeIsSelf(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
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
        property: { sample in sample >= 0 },
        formatCounterexample: { sample, _ in
            "x = \(sample); expected x >= 0"
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
