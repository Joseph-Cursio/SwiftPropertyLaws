import PropertyBased

/// Run `RawRepresentable` protocol laws over `Value` (PRD §4.3).
///
/// `RawRepresentable` carries one Strict-tier law:
///
/// - **Round-trip fidelity**: `T(rawValue: x.rawValue) == x` for every value
///   the generator produces.
///
/// `Equatable` is required by the API (the law uses `==`) but
/// `RawRepresentable` does not refine `Equatable` in the stdlib hierarchy —
/// no inherited suite runs. Callers who want Equatable's own laws should
/// invoke `checkEquatablePropertyLaws` separately.
@discardableResult
public func checkRawRepresentablePropertyLaws<
    Value: RawRepresentable & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkRoundTrip(generator: generator, options: options)
        ]
    }
}

private func checkRoundTrip<
    Value: RawRepresentable & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "RawRepresentable.roundTrip",
        generator: generator,
        options: options,
        property: { sample in
            guard let round = Value(rawValue: sample.rawValue) else { return false }
            return round == sample
        },
        formatCounterexample: { sample, _ in
            let raw = sample.rawValue
            if let round = Value(rawValue: raw) {
                return "x = \(sample), x.rawValue = \(raw); "
                    + "T(rawValue: x.rawValue) = \(round), expected x"
            }
            return "x = \(sample), x.rawValue = \(raw); "
                + "T(rawValue: x.rawValue) returned nil"
        }
    )
}
