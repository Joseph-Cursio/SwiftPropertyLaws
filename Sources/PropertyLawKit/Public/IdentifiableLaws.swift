import PropertyBased

/// Run `Identifiable` protocol laws over `Value` (PRD §4.3).
///
/// One Conventional-tier law:
///
/// - **Id stability within a process**: `x.id == x.id` for every value the
///   generator produces. Reading `id` twice on the same instance must return
///   equal values. Cross-process stability (the same logical entity getting
///   the same id across program runs) is contextual and *not* checked.
///
/// `Identifiable` does not refine any other `KnownProtocol`, so no inherited
/// suite runs. The API requires `Value.ID: Sendable` so the captured id
/// values can travel through the property-based backend's `@Sendable`
/// closures.
@discardableResult
public func checkIdentifiablePropertyLaws<
    Value: Identifiable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] where Value.ID: Sendable {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkIdStability(generator: generator, options: options)
    ]
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkIdStability<
    Value: Identifiable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult where Value.ID: Sendable {
    await runUnaryLaw(
        "Identifiable.idStability",
        tier: .conventional,
        generator: generator,
        options: options,
        property: { sample in sample.id == sample.id },
        formatCounterexample: { sample, _ in
            let first = sample.id
            let second = sample.id
            return "x = \(sample); x.id evaluated twice: \(first) ≠ \(second)"
        }
    )
}
