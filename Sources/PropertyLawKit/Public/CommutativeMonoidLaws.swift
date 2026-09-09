import PropertyBased

/// Run `CommutativeMonoid` protocol laws over `Value` (PRD §4.3 v1.9 — kit-defined).
///
/// Default `laws: .all` runs the inherited `Monoid` suite first (which
/// itself auto-recurses `Semigroup`) per PRD §4.3 inheritance semantics;
/// `.ownOnly` skips the inherited checks.
///
/// Returned-array order: inherited laws first (when `.all`) — Semigroup's
/// `combineAssociativity`, then Monoid's `combineLeftIdentity` /
/// `combineRightIdentity` — followed by the one CommutativeMonoid own law:
/// `combineCommutativity` (Strict).
///
/// **Generator caveat shared with Semigroup / Monoid.** Some commutative
/// monoids grow under `combine` (e.g. multiset union); use small-input
/// generators so the per-trial allocation cost stays bounded.
@discardableResult
public func checkCommutativeMonoidPropertyLaws<
    Value: CommutativeMonoid & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkCommutativeMonoidPropertyLaws(from: .sampling(generator), options: options, laws: laws)
}

/// The same laws over **every case** of a bounded carrier.
///
/// This is the shape the algebraic laws want. `CommutativeMonoid`'s laws are
/// universally quantified over two or three values of one carrier, so a carrier
/// small enough to enumerate turns "held for 1 000 random triples" into "holds",
/// with no budget to choose and no combination left unreached. An eight-element
/// carrier is 512 triples — a walk, not a sample.
///
/// `options.budget` is ignored; a walk's size is a property of the carrier.
/// Cap an oversized carrier explicitly with `Enumeration.prefix(_:)`, and the
/// result reports the shortfall rather than claiming completeness.
@discardableResult
public func checkCommutativeMonoidPropertyLaws<Value: CommutativeMonoid & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkCommutativeMonoidPropertyLaws(from: .enumerated(carrier), options: options, laws: laws)
}

/// The same laws over **random draws from** a bounded carrier, keeping the index.
///
/// For a carrier too large to walk. Unlike handing `carrier.generator` to the
/// sampled entry, this keeps the index inside the driver, so a failure shrinks
/// toward the smallest case and the run reports how many distinct cases it drew.
/// `options.budget` decides the number of draws.
@discardableResult
public func checkCommutativeMonoidPropertyLaws<Value: CommutativeMonoid & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    sampling carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkCommutativeMonoidPropertyLaws(from: .sampledFromSpace(carrier), options: options, laws: laws)
}

/// One assembler, two sources — so a walked suite can never run a different set
/// of laws from the sampled one.
func checkCommutativeMonoidPropertyLaws<Value: CommutativeMonoid & Equatable & Sendable>(
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
        results.append(await checkCombineCommutativity(source: source, options: options))
        return results
    }
}

private func checkCombineCommutativity<
    Value: CommutativeMonoid & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "CommutativeMonoid.combineCommutativity",
        source: source,
        options: options,
        property: { one, two in
            Value.combine(one, two) == Value.combine(two, one)
        },
        formatCounterexample: { one, two, _ in
            let lhs = Value.combine(one, two)
            let rhs = Value.combine(two, one)
            return "x = \(one), y = \(two); "
                + "combine(x, y) = \(lhs), "
                + "combine(y, x) = \(rhs)"
        }
    )
}
