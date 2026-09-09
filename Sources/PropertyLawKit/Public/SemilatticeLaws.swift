import PropertyBased

/// Run `Semilattice` protocol laws over `Value` (PRD §4.3 v1.9 — kit-defined).
///
/// Default `laws: .all` runs the inherited `CommutativeMonoid` suite first
/// (which itself auto-recurses `Monoid` and transitively `Semigroup`) per
/// PRD §4.3 inheritance semantics; `.ownOnly` skips the inherited checks.
///
/// Returned-array order: inherited laws first (when `.all`) — Semigroup's
/// `combineAssociativity`, Monoid's `combineLeftIdentity` /
/// `combineRightIdentity`, then CommutativeMonoid's `combineCommutativity`
/// — followed by the one Semilattice own law: `combineIdempotence` (Strict).
///
/// **Generator caveat.** Idempotence checks run a single sample (no growth
/// concern); the inherited associativity check is three-way. Same per-trial
/// cost as the standalone Semigroup check.
@discardableResult
public func checkSemilatticePropertyLaws<
    Value: Semilattice & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkSemilatticePropertyLaws(from: .sampling(generator), options: options, laws: laws)
}

/// The same laws over **every case** of a bounded carrier.
///
/// This is the shape the algebraic laws want. `Semilattice`'s laws are
/// universally quantified over two or three values of one carrier, so a carrier
/// small enough to enumerate turns "held for 1 000 random triples" into "holds",
/// with no budget to choose and no combination left unreached. An eight-element
/// carrier is 512 triples — a walk, not a sample.
///
/// `options.budget` is ignored; a walk's size is a property of the carrier.
/// Cap an oversized carrier explicitly with `Enumeration.prefix(_:)`, and the
/// result reports the shortfall rather than claiming completeness.
@discardableResult
public func checkSemilatticePropertyLaws<Value: Semilattice & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkSemilatticePropertyLaws(from: .enumerated(carrier), options: options, laws: laws)
}

/// One assembler, two sources — so a walked suite can never run a different set
/// of laws from the sampled one.
func checkSemilatticePropertyLaws<Value: Semilattice & Equatable & Sendable>(
    from source: InputSource<Value>,
    options: LawCheckOptions,
    laws: LawSelection
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkCommutativeMonoidPropertyLaws(from: source, options: $0, laws: .all)
            })
        }
        results.append(await checkCombineIdempotence(source: source, options: options))
        return results
    }
}

private func checkCombineIdempotence<
    Value: Semilattice & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Semilattice.combineIdempotence",
        source: source,
        options: options,
        property: { sample in
            Value.combine(sample, sample) == sample
        },
        formatCounterexample: { sample, _ in
            let actual = Value.combine(sample, sample)
            return "x = \(sample); combine(x, x) = \(actual), expected x"
        }
    )
}
