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
    try await runPropertyLawSuite(options: options) {
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
        return results
    }
}

// MARK: - Conversion + size invariants

private func checkStringInitRoundTrip<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.stringInitRoundTrip",
        generator: generator,
        options: options,
        property: { sample in
            let onceConverted = String(sample)
            let twiceConverted = String(String(sample))
            return onceConverted == twiceConverted
        },
        formatCounterexample: stringInitRoundTripCounterexample
    )
}

// MARK: - Counterexample formatters
//
// Each law's counterexample text is extracted into a named internal function
// (passed to `runUnaryLaw` by reference rather than inlined as a closure) so
// the diagnostic strings are directly unit-testable. These paths are otherwise
// unreachable through a real check run: `String`/`Substring` are the only
// stdlib `StringProtocol` conformers and both satisfy every law, and several
// laws (e.g. `stringInitRoundTrip`) cannot be violated by *any* conformer
// because they reduce to `String(x) == String(x)`.

func stringInitRoundTripCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    let once = String(sample)
    let twice = String(String(sample))
    return "x = \(sample); String(x) = \"\(once)\"; "
        + "String(String(x)) = \"\(twice)\""
}

private func checkCountMatchesStringInit<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.countMatchesStringInit",
        generator: generator,
        options: options,
        property: { sample in sample.count == String(sample).count },
        formatCounterexample: countMatchesStringInitCounterexample
    )
}

func countMatchesStringInitCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    "x = \(sample); x.count = \(sample.count), "
        + "String(x).count = \(String(sample).count)"
}

private func checkIsEmptyMatchesCountZero<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.isEmptyMatchesCountZero",
        generator: generator,
        options: options,
        property: { sample in sample.isEmpty == (sample.count == 0) },
        formatCounterexample: isEmptyMatchesCountZeroCounterexample
    )
}

func isEmptyMatchesCountZeroCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    "x = \(sample); x.isEmpty = \(sample.isEmpty), x.count == 0 = \(sample.count == 0)"
}

// MARK: - Prefix / suffix invariants

private func checkHasPrefixEmpty<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.hasPrefixEmpty",
        generator: generator,
        options: options,
        property: { sample in sample.hasPrefix("") },
        formatCounterexample: hasPrefixEmptyCounterexample
    )
}

func hasPrefixEmptyCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    let result = sample.hasPrefix("")
    return "x = \(sample); x.hasPrefix(empty) = \(result)"
}

private func checkHasSuffixEmpty<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.hasSuffixEmpty",
        generator: generator,
        options: options,
        property: { sample in sample.hasSuffix("") },
        formatCounterexample: hasSuffixEmptyCounterexample
    )
}

func hasSuffixEmptyCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    let result = sample.hasSuffix("")
    return "x = \(sample); x.hasSuffix(empty) = \(result)"
}

// MARK: - Case folding

private func checkLowercasedIdempotent<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.lowercasedIdempotent",
        generator: generator,
        options: options,
        property: { sample in
            let once = sample.lowercased()
            let twice = once.lowercased()
            return once == twice
        },
        formatCounterexample: lowercasedIdempotentCounterexample
    )
}

func lowercasedIdempotentCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    let once = sample.lowercased()
    let twice = once.lowercased()
    return "x = \(sample); x.lowercased() = \"\(once)\"; "
        + ".lowercased().lowercased() = \"\(twice)\""
}

private func checkUppercasedIdempotent<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.uppercasedIdempotent",
        generator: generator,
        options: options,
        property: { sample in
            let once = sample.uppercased()
            let twice = once.uppercased()
            return once == twice
        },
        formatCounterexample: uppercasedIdempotentCounterexample
    )
}

func uppercasedIdempotentCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    let once = sample.uppercased()
    let twice = once.uppercased()
    return "x = \(sample); x.uppercased() = \"\(once)\"; "
        + ".uppercased().uppercased() = \"\(twice)\""
}

// MARK: - UTF-8 view invariance

private func checkUtf8ViewInvariance<
    Value: StringProtocol & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StringProtocol.utf8ViewInvariance",
        generator: generator,
        options: options,
        property: { sample in
            // The UTF-8 view of a StringProtocol value must equal the
            // UTF-8 view of its String conversion — i.e. encoding is
            // invariant of the view (Substring vs String shouldn't
            // change byte-level representation).
            Array(sample.utf8) == Array(String(sample).utf8)
        },
        formatCounterexample: utf8ViewInvarianceCounterexample
    )
}

func utf8ViewInvarianceCounterexample<Value: StringProtocol & Sendable>(
    _ sample: Value,
    _ error: ErrorBox?
) -> String {
    let viaSelf = Array(sample.utf8)
    let viaString = Array(String(sample).utf8)
    return "x = \(sample); x.utf8 = \(viaSelf); "
        + "String(x).utf8 = \(viaString)"
}
