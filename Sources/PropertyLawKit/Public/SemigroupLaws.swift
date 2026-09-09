import PropertyBased

/// Run `Semigroup` protocol laws over `Value` (PRD §4.3 v1.8 — kit-defined).
///
/// One Strict-tier algebraic law — a violation is a bug:
/// - `combineAssociativity` — `combine(combine(a, b), c) == combine(a, combine(b, c))`
///
/// `Semigroup` does not refine `Equatable` in the kit's protocol decl
/// (the law check requires `Equatable`, but a type can declare `Semigroup`
/// without conforming to `Equatable` — the unverified case). The signature
/// here pins both because the law can't be checked otherwise.
///
/// **Generator caveat for unbounded combine.** Some semigroups grow
/// without bound under `combine` (e.g. string concat — `"a" • "b" • "c"`
/// produces a 3-char string from 1-char inputs). For three-way
/// associativity sampling, prefer generators producing small inputs
/// (`Gen<Character>.letterOrNumber.string(of: 0...4)` rather than
/// `0...64`) so the trial budget doesn't slow under nested allocation.
@discardableResult
public func checkSemigroupPropertyLaws<
    Value: Semigroup & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkSemigroupPropertyLaws(from: .sampling(generator), options: options)
}

/// The same laws over **every case** of a bounded carrier.
///
/// This is the shape the algebraic laws want. `Semigroup`'s laws are
/// universally quantified over two or three values of one carrier, so a carrier
/// small enough to enumerate turns "held for 1 000 random triples" into "holds",
/// with no budget to choose and no combination left unreached. An eight-element
/// carrier is 512 triples — a walk, not a sample.
///
/// `options.budget` is ignored; a walk's size is a property of the carrier.
/// Cap an oversized carrier explicitly with `Enumeration.prefix(_:)`, and the
/// result reports the shortfall rather than claiming completeness.
@discardableResult
public func checkSemigroupPropertyLaws<Value: Semigroup & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkSemigroupPropertyLaws(from: .enumerated(carrier), options: options)
}

/// The same laws over **random draws from** a bounded carrier, keeping the index.
///
/// For a carrier too large to walk. Unlike handing `carrier.generator` to the
/// sampled entry, this keeps the index inside the driver, so a failure shrinks
/// toward the smallest case and the run reports how many distinct cases it drew.
/// `options.budget` decides the number of draws.
@discardableResult
public func checkSemigroupPropertyLaws<Value: Semigroup & Equatable & Sendable>(
    for type: Value.Type = Value.self,
    sampling carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkSemigroupPropertyLaws(from: .sampledFromSpace(carrier), options: options)
}

/// One assembler, two sources — so a walked suite can never run a different set
/// of laws from the sampled one.
func checkSemigroupPropertyLaws<Value: Semigroup & Equatable & Sendable>(
    from source: InputSource<Value>,
    options: LawCheckOptions
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkCombineAssociativity(source: source, options: options)
        ]
    }
}

private func checkCombineAssociativity<
    Value: Semigroup & Equatable & Sendable
>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runTernaryLaw(
        "Semigroup.combineAssociativity",
        source: source,
        options: options,
        property: { one, two, three in
            let leftGrouped = Value.combine(Value.combine(one, two), three)
            let rightGrouped = Value.combine(one, Value.combine(two, three))
            return leftGrouped == rightGrouped
        },
        formatCounterexample: { one, two, three, _ in
            let lhs = Value.combine(Value.combine(one, two), three)
            let rhs = Value.combine(one, Value.combine(two, three))
            return "x = \(one), y = \(two), z = \(three); "
                + "combine(combine(x, y), z) = \(lhs), "
                + "combine(x, combine(y, z)) = \(rhs)"
        }
    )
}
