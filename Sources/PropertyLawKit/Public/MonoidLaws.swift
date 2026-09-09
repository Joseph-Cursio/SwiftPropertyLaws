import PropertyBased

/// Run `Monoid` protocol laws over `Value` (PRD §4.3 v1.8 — kit-defined).
///
/// Default `laws: .all` runs the inherited `Semigroup` suite first per
/// PRD §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: inherited laws first (when `.all`), then the
/// two Monoid own laws — `combineLeftIdentity`, `combineRightIdentity`
/// (both Strict).
///
/// **Generator caveat shared with Semigroup.** Some monoids grow under
/// `combine` (e.g. string concat). Identity laws use single samples so
/// allocation isn't multiplied, but the inherited associativity check
/// is three-way; same per-trial cost as the standalone Semigroup check.
@discardableResult
public func checkMonoidPropertyLaws<
    Value: Monoid & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkMonoidPropertyLaws(from: .sampling(generator), options: options, laws: laws)
}

/// The same laws over **every case** of a bounded carrier.
///
/// This is the shape the algebraic laws want. `Monoid`'s laws are
/// universally quantified over two or three values of one carrier, so a carrier
/// small enough to enumerate turns "held for 1 000 random triples" into "holds",
/// with no budget to choose and no combination left unreached. An eight-element
/// carrier is 512 triples — a walk, not a sample.
///
/// `options.budget` is ignored; a walk's size is a property of the carrier.
/// Cap an oversized carrier explicitly with `Enumeration.prefix(_:)`, and the
/// result reports the shortfall rather than claiming completeness.
@discardableResult
public func checkMonoidPropertyLaws<Value: Monoid & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkMonoidPropertyLaws(from: .enumerated(carrier), options: options, laws: laws)
}

/// The same laws over **random draws from** a bounded carrier, keeping the index.
///
/// For a carrier too large to walk. Unlike handing `carrier.generator` to the
/// sampled entry, this keeps the index inside the driver, so a failure shrinks
/// toward the smallest case and the run reports how many distinct cases it drew.
/// `options.budget` decides the number of draws.
@discardableResult
public func checkMonoidPropertyLaws<Value: Monoid & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    sampling carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkMonoidPropertyLaws(from: .sampledFromSpace(carrier), options: options, laws: laws)
}

/// One assembler, two sources — so a walked suite can never run a different set
/// of laws from the sampled one.
func checkMonoidPropertyLaws<Value: Monoid & Equatable & Sendable>(
    from source: InputSource<Value>,
    options: LawCheckOptions,
    laws: LawSelection
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkSemigroupPropertyLaws(from: source, options: $0)
            })
        }
        results.append(contentsOf: [
            await checkCombineLeftIdentity(source: source, options: options),
            await checkCombineRightIdentity(source: source, options: options)
        ])
        return results
    }
}

private func checkCombineLeftIdentity<
    Value: Monoid & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Monoid.combineLeftIdentity",
        source: source,
        options: options,
        property: { sample in
            Value.combine(Value.identity, sample) == sample
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(Value.identity, sample)
            return "x = \(sample); combine(.identity, x) = \(actual), expected x"
        }
    )
}

private func checkCombineRightIdentity<
    Value: Monoid & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Monoid.combineRightIdentity",
        source: source,
        options: options,
        property: { sample in
            Value.combine(sample, Value.identity) == sample
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(sample, Value.identity)
            return "x = \(sample); combine(x, .identity) = \(actual), expected x"
        }
    )
}
