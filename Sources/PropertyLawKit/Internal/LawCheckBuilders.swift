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

/// One-value law: `property(x)` must hold for every sampled `x`.
func runUnaryLaw<Value: Sendable, Shrinker: SendableSequenceType>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    observation: PerLawDriver.Observation<Value> = PerLawDriver.Observation(),
    property: @escaping @Sendable (Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: protocolLaw,
        tier: tier,
        options: options,
        check: LawCheck(
            sample: { rng in generator.run(using: &rng) },
            property: property,
            formatCounterexample: formatCounterexample,
            shrink: shrink
        ),
        observation: observation
    )
}

/// Two-value law: `property(x, y)` must hold for every sampled pair.
func runBinaryLaw<Value: Sendable, Shrinker: SendableSequenceType>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
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
            sample: { rng in (generator.run(using: &rng), generator.run(using: &rng)) },
            property: { try await property($0.0, $0.1) },
            formatCounterexample: { formatCounterexample($0.0, $0.1, $1) },
            shrink: tupleShrink
        )
    )
}

/// Three-value law: `property(x, y, z)` must hold for every sampled triple.
///
/// Ternary shrinking is deferred (v2.4 covers unary + binary): a 3-value law's
/// counterexample is relational, so minimizing each component independently is
/// of marginal value, and the explicit `(Value, Value, Value)` shrinker type
/// would be the kit's only `large_tuple` site. Triple laws report the first
/// failing triple verbatim, exactly as before v2.4.
func runTernaryLaw<Value: Sendable, Shrinker: SendableSequenceType>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    generator: Generator<Value, Shrinker>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, Value, ErrorBox?) -> String
) async -> CheckResult {
    await PerLawDriver.run(
        protocolLaw: protocolLaw,
        tier: tier,
        options: options,
        check: LawCheck(
            sample: { rng in
                (generator.run(using: &rng), generator.run(using: &rng), generator.run(using: &rng))
            },
            property: { try await property($0.0, $0.1, $0.2) },
            formatCounterexample: { formatCounterexample($0.0, $0.1, $0.2, $1) }
        )
    )
}
