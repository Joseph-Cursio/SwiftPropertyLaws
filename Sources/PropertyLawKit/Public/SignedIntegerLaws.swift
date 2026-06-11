import PropertyBased

/// Run `SignedInteger` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `BinaryInteger` and `SignedNumeric`
/// suites first per PRD §4.3 inheritance semantics — `SignedInteger` sits at
/// the diamond, refining both — followed by the one own law. `.ownOnly`
/// skips both inherited suites.
///
/// Returned-array order: inherited BinaryInteger → SignedNumeric → own.
///
/// `SignedInteger`'s own contract is mostly representational; the bulk of
/// useful coverage comes from the two inherited suites. The single own law
/// guards against custom conformers whose `signum()` disagrees with the
/// signedness comparisons.
@discardableResult
public func checkSignedIntegerPropertyLaws<
    Value: SignedInteger & Sendable,
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
        results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
            // SignedNumeric's own laws only — skipping its inherited Numeric suite
            // here because the BinaryInteger collector already ran Numeric. Without
            // the .ownOnly cap we'd run Numeric's six laws twice.
            try await checkSignedNumericPropertyLaws(
                for: type,
                using: generator,
                options: $0,
                laws: .ownOnly
            )
        })
    }
    results.append(contentsOf: [
        await checkSignednessConsistency(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkSignednessConsistency<
    Value: SignedInteger & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "SignedInteger.signednessConsistency",
        generator: generator,
        options: options,
        property: { sample in
            let signum = sample.signum()
            if sample > 0 { return signum == 1 }
            if sample < 0 { return signum == -1 }
            return signum == 0
        },
        formatCounterexample: { sample, _ in
            "x = \(sample); x.signum() = \(sample.signum()); "
                + "x ⋚ 0 ⇒ signum should be 1/0/-1"
        }
    )
}
