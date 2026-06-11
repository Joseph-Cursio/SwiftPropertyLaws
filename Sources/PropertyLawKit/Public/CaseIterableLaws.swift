import PropertyBased

/// Run `CaseIterable` protocol laws over `Value` (PRD §4.3).
///
/// One Strict-tier law:
///
/// - **Exactly-once enumeration**: `allCases` lists each case exactly once
///   (`Set(allCases).count == allCases.count`). For compiler-synthesized
///   conformances on enums this holds by construction; the check is the
///   self-test gate against hand-rolled `allCases` getters that
///   accidentally drop or duplicate cases.
///
/// The check is static — `allCases` is a deterministic, sample-independent
/// value. The `using:` parameter is accepted for API symmetry with the rest
/// of the kit but is not consulted by the law itself; pass any generator
/// that produces `Value` (e.g., the same one you'd hand to
/// `checkEquatablePropertyLaws`).
///
/// `CaseIterable` is on the macro/plugin's `unemittable` list — types that
/// declare `: CaseIterable` don't get this check emitted automatically;
/// callers invoke it manually when they want it. The Conventional rationale
/// is that most `: CaseIterable` adoptions exist to expose `allCases` for
/// list iteration, not to test protocol-level correctness, and synthesized
/// conformances never violate this law.
@discardableResult
public func checkCaseIterablePropertyLaws<
    Value: CaseIterable & Hashable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    _ = generator
    return try await runPropertyLawSuite(options: options) {
        [
            await checkExactlyOnce(for: type, options: options)
        ]
    }
}

private func checkExactlyOnce<Value: CaseIterable & Hashable & Sendable>(
    for type: Value.Type,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "CaseIterable.exactlyOnce",
        tier: .strict,
        options: options,
        check: LawCheck<Void>(
            sample: { _ in () },
            property: { _ in
                let cases = Array(Value.allCases)
                return Set(cases).count == cases.count
            },
            formatCounterexample: { _, _ in
                let cases = Array(Value.allCases)
                let duplicates = Dictionary(grouping: cases, by: { $0 })
                    .compactMapValues { $0.count > 1 ? $0.count : nil }
                return "T.allCases has \(cases.count) entries but only "
                    + "\(Set(cases).count) unique values; duplicates: \(duplicates)"
            }
        )
    )
}
