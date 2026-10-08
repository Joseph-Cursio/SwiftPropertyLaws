import PropertyBased

/// Drives the three laws that need equal values over one pool of draws
/// (``EqualValuePairing``) rather than an independent pair per trial.
///
/// **The pool is drawn one value at a time, and each new draw is compared with
/// the earlier ones.** So a failure is found at the first draw that completes a
/// refuting pair, the run stops there, and what it drew is a prefix of one
/// seeded stream — which is the whole replay contract: the same seed redraws the
/// same prefix and meets the same pair. No backend is consulted, for
/// `AggregateDriver`'s reason: the loop is the kit's, and a backend that
/// reordered or redrew it would break the contract rather than vary it.
///
/// A failing pair shrinks exactly as a sampled one does — the minimizer re-runs
/// the law's own property, and the pair no longer needs the pool once found.
enum DrawPoolDriver {

    struct Identity {
        let protocolLaw: String
        let tier: StrictnessTier
    }

    /// A two-value law over the pool: each new draw is paired with every earlier
    /// draw within `lookback`, earlier draw first.
    struct PairCheck<Value: Sendable>: Sendable {
        let sample: @Sendable (inout Xoshiro) -> Value
        let property: @Sendable (Value, Value) async throws -> Bool
        let formatCounterexample: @Sendable (Value, Value, ErrorBox?) -> String
        let shrink: (@Sendable (Value) -> [Value])?
    }

    static func runPairs<Value: Sendable>(
        _ identity: Identity,
        options: LawCheckOptions,
        lookback: Int,
        check: PairCheck<Value>
    ) async -> CheckResult {
        let verdict = Verdict<(Value, Value)>(
            property: { try await check.property($0.0, $0.1) },
            formatCounterexample: { check.formatCounterexample($0.0, $0.1, $1) },
            shrink: liftToPairShrinker(check.shrink)
        )
        return await run(identity, options: options, verdict: verdict) { rng, budget in
            var pool: [Value] = []
            pool.reserveCapacity(budget)
            var pairs = 0
            for _ in 0 ..< budget {
                let draw = check.sample(&rng)
                for earlier in pool[max(0, pool.count - lookback)...] {
                    pairs += 1
                    do {
                        if try await check.property(earlier, draw) { continue }
                        return Walk(draws: pool.count + 1, pairs: pairs, failure: ((earlier, draw), nil))
                    } catch {
                        return Walk(draws: pool.count + 1, pairs: pairs, failure: ((earlier, draw), ErrorBox(error)))
                    }
                }
                pool.append(draw)
            }
            return Walk(draws: pool.count, pairs: pairs, failure: nil)
        }
    }

    // `large_tuple` is waived here for the reason `LawCheckBuilders` gives: a
    // three-value law's input is intrinsically a triple.
    // swiftlint:disable large_tuple

    /// A three-value law whose antecedent is a chain, `link(x, y) && link(y, z)`.
    ///
    /// Not every triple of the pool — that is cubic, a billion at the default
    /// budget. The pairs are linked as they are compared, and only triples that
    /// form a chain reach `property`; every other triple has a false antecedent,
    /// so it could not have failed. Each chain is examined once, at the draw of
    /// its latest member, in both directions.
    struct ChainCheck<Value: Sendable>: Sendable {
        let sample: @Sendable (inout Xoshiro) -> Value
        let link: @Sendable (Value, Value) -> Bool
        let property: @Sendable (Value, Value, Value) async throws -> Bool
        let formatCounterexample: @Sendable (Value, Value, Value, ErrorBox?) -> String
        let shrink: (@Sendable (Value) -> [Value])?
    }

    static func runChains<Value: Sendable>(
        _ identity: Identity,
        options: LawCheckOptions,
        lookback: Int,
        check: ChainCheck<Value>
    ) async -> CheckResult {
        let verdict = Verdict<(Value, Value, Value)>(
            property: { try await check.property($0.0, $0.1, $0.2) },
            formatCounterexample: { check.formatCounterexample($0.0, $0.1, $0.2, $1) },
            shrink: liftToTripleShrinker(check.shrink)
        )
        return await run(identity, options: options, verdict: verdict) { rng, budget in
            var pool: [Value] = []
            pool.reserveCapacity(budget)
            var linked: [[Int]] = []
            var pairs = 0
            for _ in 0 ..< budget {
                let draw = check.sample(&rng)
                let newest = pool.count
                var neighbours: [Int] = []
                for earlier in max(0, newest - lookback) ..< newest {
                    pairs += 1
                    if check.link(pool[earlier], draw) { neighbours.append(earlier) }
                }
                pool.append(draw)
                for (first, second, third) in chains(completedBy: newest, neighbours: neighbours, linked: linked) {
                    let triple = (pool[first], pool[second], pool[third])
                    do {
                        if try await check.property(triple.0, triple.1, triple.2) { continue }
                        return Walk(draws: pool.count, pairs: pairs, failure: (triple, nil))
                    } catch {
                        return Walk(draws: pool.count, pairs: pairs, failure: (triple, ErrorBox(error)))
                    }
                }
                for earlier in neighbours { linked[earlier].append(newest) }
                linked.append(neighbours)
            }
            return Walk(draws: pool.count, pairs: pairs, failure: nil)
        }
    }

    /// The chains `newest` completes: through an earlier middle it just linked
    /// to, and through itself as the middle of two earlier draws.
    private static func chains(
        completedBy newest: Int,
        neighbours: [Int],
        linked: [[Int]]
    ) -> [(Int, Int, Int)] {
        var chains: [(Int, Int, Int)] = []
        for middle in neighbours {
            for end in linked[middle] {
                chains.append((end, middle, newest))
                chains.append((newest, middle, end))
            }
        }
        for (position, first) in neighbours.enumerated() {
            for second in neighbours[(position + 1)...] {
                chains.append((first, newest, second))
                chains.append((second, newest, first))
            }
        }
        return chains
    }
    // swiftlint:enable large_tuple

    /// How a failure is judged once found: the law's own property (re-run by the
    /// shrinker), its message, and how to shrink it.
    private struct Verdict<Input: Sendable>: Sendable {
        let property: @Sendable (Input) async throws -> Bool
        let formatCounterexample: @Sendable (Input, ErrorBox?) -> String
        let shrink: (@Sendable (Input) -> [Input])?
    }

    /// How far a pooled loop got and, if it stopped early, what stopped it.
    private struct Walk<Input: Sendable>: Sendable {
        let draws: Int
        let pairs: Int
        let failure: (input: Input, error: ErrorBox?)?
    }

    private static func run<Input: Sendable>(
        _ identity: Identity,
        options: LawCheckOptions,
        verdict: Verdict<Input>,
        loop: (inout Xoshiro, Int) async -> Walk<Input>
    ) async -> CheckResult {
        let environment = Environment.current(backend: options.backend)
        if let early = CheckPreflight.earlyResult(
            protocolLaw: identity.protocolLaw, tier: identity.tier, options: options, environment: environment
        ) {
            return early
        }
        var rng = options.seed?.makeXoshiro() ?? Xoshiro()
        let initialSeed = Seed(xoshiro: rng)
        let walk = await loop(&rng, options.budget.trialCount)
        var result = CheckResult(
            protocolLaw: identity.protocolLaw,
            tier: identity.tier,
            trials: walk.draws,
            seed: initialSeed,
            environment: environment,
            outcome: .passed,
            pairedDraws: PairedDraws(draws: walk.draws, pairs: walk.pairs)
        )
        if let failure = walk.failure {
            var minimal = PerLawDriver.Minimized(input: failure.input, steps: 0, error: failure.error)
            if let shrink = verdict.shrink {
                minimal = await PerLawDriver.minimize(
                    failure.input, firstError: failure.error, shrink: shrink, property: verdict.property)
            }
            result.outcome = .failed(counterexample: verdict.formatCounterexample(minimal.input, minimal.error))
            result.shrinkSteps = minimal.steps
            result.shrunkFrom = minimal.steps > 0
                ? verdict.formatCounterexample(failure.input, failure.error)
                : nil
        }
        return LawSuppressionPolicy.rewriteIfIntentional(result, in: options.suppressions)
    }
}
