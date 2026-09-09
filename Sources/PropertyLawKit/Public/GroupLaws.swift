import PropertyBased

/// Run `Group` protocol laws over `Value` (PRD §4.3 v1.9 — kit-defined).
///
/// Default `laws: .all` runs the inherited `Monoid` suite first (which
/// itself auto-recurses `Semigroup`) per PRD §4.3 inheritance semantics;
/// `.ownOnly` skips the inherited checks.
///
/// Returned-array order: inherited laws first (when `.all`) — Semigroup's
/// `combineAssociativity`, then Monoid's `combineLeftIdentity` /
/// `combineRightIdentity` — followed by the two Group own laws:
/// `combineLeftInverse`, `combineRightInverse` (both Strict).
///
/// **Generator caveat.** Some groups grow under repeated `combine` (e.g.
/// free groups over a generator set); the inverse laws use single samples
/// so allocation isn't multiplied, but the inherited associativity check
/// is three-way — same per-trial cost as the standalone Semigroup check.
@discardableResult
public func checkGroupPropertyLaws<
    Value: Group & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkGroupPropertyLaws(from: .sampling(generator), options: options, laws: laws)
}

/// The same laws over **every case** of a bounded carrier.
///
/// This is the shape the algebraic laws want. `Group`'s laws are
/// universally quantified over two or three values of one carrier, so a carrier
/// small enough to enumerate turns "held for 1 000 random triples" into "holds",
/// with no budget to choose and no combination left unreached. An eight-element
/// carrier is 512 triples — a walk, not a sample.
///
/// `options.budget` is ignored; a walk's size is a property of the carrier.
/// Cap an oversized carrier explicitly with `Enumeration.prefix(_:)`, and the
/// result reports the shortfall rather than claiming completeness.
@discardableResult
public func checkGroupPropertyLaws<Value: Group & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkGroupPropertyLaws(from: .enumerated(carrier), options: options, laws: laws)
}

/// One assembler, two sources — so a walked suite can never run a different set
/// of laws from the sampled one.
func checkGroupPropertyLaws<Value: Group & Equatable & Sendable>(
    from source: InputSource<Value>,
    options: LawCheckOptions,
    laws: LawSelection
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkMonoidPropertyLaws(from: source, options: $0, laws: .all)
            })
        }
        results.append(contentsOf: [
            await checkCombineLeftInverse(source: source, options: options),
            await checkCombineRightInverse(source: source, options: options)
        ])
        return results
    }
}

private func checkCombineLeftInverse<
    Value: Group & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Group.combineLeftInverse",
        source: source,
        options: options,
        property: { sample in
            Value.combine(Value.inverse(sample), sample) == Value.identity
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(Value.inverse(sample), sample)
            return "x = \(sample); combine(inverse(x), x) = \(actual), expected .identity"
        }
    )
}

private func checkCombineRightInverse<
    Value: Group & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Group.combineRightInverse",
        source: source,
        options: options,
        property: { sample in
            Value.combine(sample, Value.inverse(sample)) == Value.identity
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(sample, Value.inverse(sample))
            return "x = \(sample); combine(x, inverse(x)) = \(actual), expected .identity"
        }
    )
}
