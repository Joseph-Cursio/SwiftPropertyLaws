import PropertyBased

/// Run `StringProtocol` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `BidirectionalCollection` suite
/// first (which transitively runs `Collection`, `Sequence`, and
/// `IteratorProtocol`) per PRD §4.3 inheritance semantics; `.ownOnly`
/// skips them.
///
/// Returned-array order: inherited laws first (when `.all`), then eight
/// StringProtocol laws — `stringInitRoundTrip`, `countMatchesStringInit`,
/// `isEmptyMatchesCountZero`, `hasPrefixEmpty`, `hasSuffixEmpty`,
/// `lowercasedIdempotent`, `uppercasedIdempotent`, `utf8ViewInvariance`
/// (all Strict).
///
/// `Comparable`, `Hashable`, and `LosslessStringConvertible` are not
/// auto-run: a `: StringProtocol` type that explicitly declares those
/// conformances still emits their own checks under the discovery plugin's
/// most-specific dedupe (matches the v1.4 M4 design — siblings stay
/// independent, only the linear-chain refinement is auto-traversed).
@discardableResult
public func checkStringProtocolPropertyLaws<
    Value: StringProtocol & Sendable,
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
            try await checkBidirectionalCollectionPropertyLaws(
                for: type,
                using: generator,
                options: $0
            )
        })
    }
    results.append(contentsOf: [
        await checkStringInitRoundTrip(generator: generator, options: options),
        await checkCountMatchesStringInit(generator: generator, options: options),
        await checkIsEmptyMatchesCountZero(generator: generator, options: options),
        await checkHasPrefixEmpty(generator: generator, options: options),
        await checkHasSuffixEmpty(generator: generator, options: options),
        await checkLowercasedIdempotent(generator: generator, options: options),
        await checkUppercasedIdempotent(generator: generator, options: options),
        await checkUtf8ViewInvariance(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

// MARK: - Conversion + size invariants

private func checkStringInitRoundTrip<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.stringInitRoundTrip",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                let onceConverted = String(sample)
                let twiceConverted = String(String(sample))
                return onceConverted == twiceConverted
            },
            formatCounterexample: { sample, _ in
                let once = String(sample)
                let twice = String(String(sample))
                return "x = \(sample); String(x) = \"\(once)\"; "
                    + "String(String(x)) = \"\(twice)\""
            }
        )
    )
}

private func checkCountMatchesStringInit<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.countMatchesStringInit",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.count == String(sample).count },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.count = \(sample.count), "
                    + "String(x).count = \(String(sample).count)"
            }
        )
    )
}

private func checkIsEmptyMatchesCountZero<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.isEmptyMatchesCountZero",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.isEmpty == (sample.count == 0) },
            formatCounterexample: { sample, _ in
                "x = \(sample); x.isEmpty = \(sample.isEmpty), x.count == 0 = \(sample.count == 0)"
            }
        )
    )
}

// MARK: - Prefix / suffix invariants

private func checkHasPrefixEmpty<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.hasPrefixEmpty",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.hasPrefix("") },
            formatCounterexample: { sample, _ in
                let result = sample.hasPrefix("")
                return "x = \(sample); x.hasPrefix(empty) = \(result)"
            }
        )
    )
}

private func checkHasSuffixEmpty<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.hasSuffixEmpty",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in sample.hasSuffix("") },
            formatCounterexample: { sample, _ in
                let result = sample.hasSuffix("")
                return "x = \(sample); x.hasSuffix(empty) = \(result)"
            }
        )
    )
}

// MARK: - Case folding

private func checkLowercasedIdempotent<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.lowercasedIdempotent",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                let once = sample.lowercased()
                let twice = once.lowercased()
                return once == twice
            },
            formatCounterexample: { sample, _ in
                let once = sample.lowercased()
                let twice = once.lowercased()
                return "x = \(sample); x.lowercased() = \"\(once)\"; "
                    + ".lowercased().lowercased() = \"\(twice)\""
            }
        )
    )
}

private func checkUppercasedIdempotent<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.uppercasedIdempotent",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                let once = sample.uppercased()
                let twice = once.uppercased()
                return once == twice
            },
            formatCounterexample: { sample, _ in
                let once = sample.uppercased()
                let twice = once.uppercased()
                return "x = \(sample); x.uppercased() = \"\(once)\"; "
                    + ".uppercased().uppercased() = \"\(twice)\""
            }
        )
    )
}

// MARK: - UTF-8 view invariance

private func checkUtf8ViewInvariance<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: "StringProtocol.utf8ViewInvariance",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: { sample in
                // The UTF-8 view of a StringProtocol value must equal the
                // UTF-8 view of its String conversion — i.e. encoding is
                // invariant of the view (Substring vs String shouldn't
                // change byte-level representation).
                Array(sample.utf8) == Array(String(sample).utf8)
            },
            formatCounterexample: { sample, _ in
                let viaSelf = Array(sample.utf8)
                let viaString = Array(String(sample).utf8)
                return "x = \(sample); x.utf8 = \(viaSelf); "
                    + "String(x).utf8 = \(viaString)"
            }
        )
    )
}
