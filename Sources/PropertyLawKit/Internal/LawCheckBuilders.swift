import PropertyBased

// Convenience wrappers over `PerLawDriver.run` for the three overwhelmingly
// common per-law shapes: a property over one, two, or three values drawn
// independently from the same generator. Each builds the `LawCheck.sample`
// closure (N× `generator.run`) and, for the multi-value forms, destructures
// the sampled tuple so call sites declare only the law identity, the
// property, and the counterexample text — not the sampling/packaging
// boilerplate every law otherwise repeats.
//
// `tier` defaults to `.strict` (128 of the kit's 138 laws); Conventional /
// Heuristic laws pass it explicitly. Keeping it defaulted also holds each
// helper at the five-parameter lint ceiling.
//
// Laws whose sampling isn't "N independent draws from one generator"
// (sequence generators, paired stride generators, bespoke `Int.random`
// draws) call `PerLawDriver.run` directly.

// v2.4 shrinking: each builder takes an optional per-element shrinker
// `(Value) -> [Value]` (default `nil` ⇒ no shrinking, identical to pre-v2.4).
// The multi-value forms lift it into a tuple shrinker that shrinks one
// position at a time, holding the others fixed — the standard "shrink each
// component independently" strategy.

/// One-value law: `property(x)` must hold for every `x` the source supplies.
///
/// `observation` is honoured on the sampled path only. The enumerated path
/// reports `SpaceCoverage` instead, which answers the question near-miss and
/// class tracking exist to approximate — how much of the input space was
/// actually reached — as a count rather than as a sample of hints.
package func runUnaryLaw<Value: Sendable>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    source: InputSource<Value>,
    options: LawCheckOptions,
    observation: PerLawDriver.Observation<Value> = PerLawDriver.Observation(),
    property: @escaping @Sendable (Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    switch source {
    case .sampled(let sample):
        return await PerLawDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            check: LawCheck(
                sample: sample,
                property: property,
                formatCounterexample: formatCounterexample,
                shrink: shrink
            ),
            observation: observation
        )
    case .enumerated(let space):
        return await EnumerationDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            space: space,
            property: property,
            describeFailure: formatCounterexample
        )
    case .sampledFromSpace(let space):
        let sampler = SpaceSampler(space)
        let result = await PerLawDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            check: LawCheck(
                sample: { rng in
                    let draw = sampler.draw(&rng)
                    sampler.record([draw])
                    return draw
                },
                property: { try await property($0.value) },
                formatCounterexample: { draw, error in
                    sampler.describe([draw], formatCounterexample(draw.value, error))
                },
                shrink: { sampler.shrink($0) }
            )
        )
        return result.reporting(sampler.coverage(arity: 1))
    }
}

/// One-value law over a generator — the shape every existing call site uses.
package func runUnaryLaw<Value: Sendable, Shrinker: SendableSequenceType>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    observation: PerLawDriver.Observation<Value> = PerLawDriver.Observation(),
    property: @escaping @Sendable (Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    await runUnaryLaw(
        protocolLaw,
        tier: tier,
        source: .sampling(generator),
        options: options,
        observation: observation,
        property: property,
        formatCounterexample: formatCounterexample,
        shrink: shrink
    )
}

/// Two-value law: `property(x, y)` must hold for every pair the source supplies.
///
/// Sampled, that is two independent draws per trial. Enumerated, it is
/// `Every.product(space, space)` — every ordered pair, smallest summed size
/// first — so a pair the sampled form reaches by luck is reached by
/// construction, and a pair it never reaches is reported as never reached.
package func runBinaryLaw<Value: Sendable>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    source: InputSource<Value>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    switch source {
    case .sampled(let sample):
        let tupleShrink: (@Sendable ((Value, Value)) -> [(Value, Value)])?
        if let element = shrink {
            tupleShrink = { (pair: (Value, Value)) -> [(Value, Value)] in
                let first: [(Value, Value)] = element(pair.0).map { ($0, pair.1) }
                let second: [(Value, Value)] = element(pair.1).map { (pair.0, $0) }
                return first + second
            }
        } else {
            tupleShrink = nil
        }
        return await PerLawDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            check: LawCheck(
                sample: { rng in (sample(&rng), sample(&rng)) },
                property: { try await property($0.0, $0.1) },
                formatCounterexample: { formatCounterexample($0.0, $0.1, $1) },
                shrink: tupleShrink
            )
        )
    case .enumerated(let space):
        return await EnumerationDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            space: Every.product(space, space),
            property: { try await property($0.0, $0.1) },
            describeFailure: { formatCounterexample($0.0, $0.1, $1) }
        )
    case .sampledFromSpace(let space):
        return await runBinaryLawSampling(
            protocolLaw, tier: tier, space: space, options: options,
            property: property, formatCounterexample: formatCounterexample)
    }
}

/// Two independent draws from one space rather than one draw from
/// `product(space, space)`: the composite is n squared cases, which overflows
/// for a large space, and shrinking each position separately is the strategy the
/// sampled path already uses.
private func runBinaryLawSampling<Value: Sendable>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    space: Enumeration<Value>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, ErrorBox?) -> String
) async -> CheckResult {
    let sampler = SpaceSampler(space)
    let result = await PerLawDriver.run(
        protocolLaw: protocolLaw,
        tier: tier,
        options: options,
        check: LawCheck(
            sample: { rng in
                let pair = (sampler.draw(&rng), sampler.draw(&rng))
                sampler.record([pair.0, pair.1])
                return pair
            },
            property: { try await property($0.0.value, $0.1.value) },
            formatCounterexample: { pair, error in
                sampler.describe(
                    [pair.0, pair.1],
                    formatCounterexample(pair.0.value, pair.1.value, error))
            },
            shrink: { pair in
                sampler.shrink(pair.0).map { ($0, pair.1) }
                    + sampler.shrink(pair.1).map { (pair.0, $0) }
            }
        )
    )
    return result.reporting(sampler.coverage(arity: 2))
}

/// Two-value law over a generator — the shape every existing call site uses.
package func runBinaryLaw<Value: Sendable, Shrinker: SendableSequenceType>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    await runBinaryLaw(
        protocolLaw,
        tier: tier,
        source: .sampling(generator),
        options: options,
        property: property,
        formatCounterexample: formatCounterexample,
        shrink: shrink
    )
}

// `large_tuple` is waived for this helper by design: a 3-value law's input is
// intrinsically a triple, so the shrinker's type must name `(Value, Value,
// Value)`. The waiver is scoped here rather than relaxing the project rule.
// swiftlint:disable large_tuple

/// Lift a per-element shrinker into a triple shrinker that shrinks one position
/// at a time, holding the others fixed.
private func liftToTripleShrinker<Value>(
    _ element: (@Sendable (Value) -> [Value])?
) -> (@Sendable ((Value, Value, Value)) -> [(Value, Value, Value)])? {
    guard let element else { return nil }
    return { (triple: (Value, Value, Value)) -> [(Value, Value, Value)] in
        let first: [(Value, Value, Value)] = element(triple.0).map { ($0, triple.1, triple.2) }
        let second: [(Value, Value, Value)] = element(triple.1).map { (triple.0, $0, triple.2) }
        let third: [(Value, Value, Value)] = element(triple.2).map { (triple.0, triple.1, $0) }
        return first + second + third
    }
}
// swiftlint:enable large_tuple

/// Three-value law: `property(x, y, z)` must hold for every triple the source
/// supplies.
///
/// Enumerated, that is `Every.triples(of: space)` — an 8-case carrier gives 512
/// triples, which is a walk. This is the shape the algebraic cluster is
/// quantified over, and the shape a conditional law like transitivity needs a
/// chain to reach at all.
package func runTernaryLaw<Value: Sendable>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    source: InputSource<Value>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    switch source {
    case .sampled(let sample):
        return await PerLawDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            check: LawCheck(
                sample: { rng in (sample(&rng), sample(&rng), sample(&rng)) },
                property: { try await property($0.0, $0.1, $0.2) },
                formatCounterexample: { formatCounterexample($0.0, $0.1, $0.2, $1) },
                shrink: liftToTripleShrinker(shrink)
            )
        )
    case .enumerated(let space):
        return await EnumerationDriver.run(
            protocolLaw: protocolLaw,
            tier: tier,
            options: options,
            space: Every.triples(of: space),
            property: { try await property($0.first, $0.second, $0.third) },
            describeFailure: { formatCounterexample($0.first, $0.second, $0.third, $1) }
        )
    case .sampledFromSpace(let space):
        return await runTernaryLawSampling(
            protocolLaw, tier: tier, space: space, options: options,
            property: property, formatCounterexample: formatCounterexample)
    }
}

/// `Triple` rather than a 3-tuple, for the same reason the walked path uses it:
/// three independent draws, each shrinking on its own index.
private func runTernaryLawSampling<Value: Sendable>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    space: Enumeration<Value>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, Value, ErrorBox?) -> String
) async -> CheckResult {
    let sampler = SpaceSampler(space)
    let result = await PerLawDriver.run(
        protocolLaw: protocolLaw,
        tier: tier,
        options: options,
        check: LawCheck(
            sample: { rng in
                let triple = Triple(
                    first: sampler.draw(&rng),
                    second: sampler.draw(&rng),
                    third: sampler.draw(&rng))
                sampler.record([triple.first, triple.second, triple.third])
                return triple
            },
            property: { try await property($0.first.value, $0.second.value, $0.third.value) },
            formatCounterexample: { triple, error in
                sampler.describe(
                    [triple.first, triple.second, triple.third],
                    formatCounterexample(
                        triple.first.value, triple.second.value, triple.third.value, error))
            },
            shrink: { triple in
                let firsts = sampler.shrink(triple.first).map {
                    Triple(first: $0, second: triple.second, third: triple.third)
                }
                let seconds = sampler.shrink(triple.second).map {
                    Triple(first: triple.first, second: $0, third: triple.third)
                }
                let thirds = sampler.shrink(triple.third).map {
                    Triple(first: triple.first, second: triple.second, third: $0)
                }
                return firsts + seconds + thirds
            }
        )
    )
    return result.reporting(sampler.coverage(arity: 3))
}

/// Three-value law over a generator — the shape every existing call site uses.
package func runTernaryLaw<Value: Sendable, Shrinker: SendableSequenceType>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    await runTernaryLaw(
        protocolLaw,
        tier: tier,
        source: .sampling(generator),
        options: options,
        property: property,
        formatCounterexample: formatCounterexample,
        shrink: shrink
    )
}
