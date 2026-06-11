import PropertyBased

/// Run `LosslessStringConvertible` protocol laws over `Value` (PRD §4.3).
///
/// One Strict-tier law:
///
/// - **Round-trip fidelity**: `T(String(describing: x)) == x` for every
///   value the generator produces. `String(describing:)` calls
///   `CustomStringConvertible.description` (which `LosslessStringConvertible`
///   inherits), so this is the canonical "stringify, then parse, then
///   compare" round-trip.
///
/// `Equatable` is required by the API (the law uses `==`) but
/// `LosslessStringConvertible` does not refine `Equatable` in stdlib — no
/// inherited suite runs.
@discardableResult
public func checkLosslessStringConvertiblePropertyLaws<
    Value: LosslessStringConvertible & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try ReplayEnvironmentValidator.verify(options)
    let results = [
        await checkRoundTrip(generator: generator, options: options)
    ]
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkRoundTrip<
    Value: LosslessStringConvertible & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "LosslessStringConvertible.roundTrip",
        generator: generator,
        options: options,
        property: { sample in
            guard let round = Value(String(describing: sample)) else { return false }
            return round == sample
        },
        formatCounterexample: { sample, _ in
            let described = String(describing: sample)
            if let round = Value(described) {
                return "x = \(sample), String(describing: x) = \"\(described)\"; "
                    + "T(String(describing: x)) = \(round), expected x"
            }
            return "x = \(sample), String(describing: x) = \"\(described)\"; "
                + "T(String(describing: x)) returned nil"
        }
    )
}
