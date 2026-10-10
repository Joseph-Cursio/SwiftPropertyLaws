import PropertyBased

// Builders for the three laws that need equal values — `Hashable.equalityConsistency`,
// `Equatable.transitivity`, `Comparable.antisymmetry`. Each is `runBinaryLaw` /
// `runTernaryLaw` unless the caller opted into `LawCheckOptions.equalValuePairing`,
// in which case a generator-sampled source pools its draws instead.
//
// Only `.sampled` pools. A walk reaches every pair by construction already, and a
// sampled *space* keeps an index per draw that a pool would have to carry too —
// not worth building until someone needs both at once.

/// A two-value law whose antecedent is two equal (or equivalent) values.
package func runEqualValueBinaryLaw<Value: Sendable>(
    _ protocolLaw: String,
    tier: StrictnessTier = .strict,
    source: InputSource<Value>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    guard case .sampled(let sample) = source, let lookback = options.equalValuePairing.lookback else {
        return await runBinaryLaw(
            protocolLaw, tier: tier, source: source, options: options,
            property: property, formatCounterexample: formatCounterexample, shrink: shrink)
    }
    return await DrawPoolDriver.runPairs(
        DrawPoolDriver.Identity(protocolLaw: protocolLaw, tier: tier),
        options: options,
        lookback: lookback,
        check: DrawPoolDriver.PairCheck(
            sample: sample, property: property, formatCounterexample: formatCounterexample, shrink: shrink)
    )
}

/// A three-value law whose antecedent is a chain `x == y && y == z` —
/// transitivity of `==`. Pooled, the equal pairs are linked as they are found
/// and only the chains they form are tested.
package func runEqualityChainLaw<Value: Equatable & Sendable>(
    _ protocolLaw: String,
    source: InputSource<Value>,
    options: LawCheckOptions,
    property: @escaping @Sendable (Value, Value, Value) async throws -> Bool,
    formatCounterexample: @escaping @Sendable (Value, Value, Value, ErrorBox?) -> String,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async -> CheckResult {
    guard case .sampled(let sample) = source, let lookback = options.equalValuePairing.lookback else {
        return await runTernaryLaw(
            protocolLaw, source: source, options: options,
            property: property, formatCounterexample: formatCounterexample, shrink: shrink)
    }
    return await DrawPoolDriver.runChains(
        DrawPoolDriver.Identity(protocolLaw: protocolLaw, tier: .strict),
        options: options,
        lookback: lookback,
        check: DrawPoolDriver.ChainCheck(
            sample: sample, link: { $0 == $1 }, property: property,
            formatCounterexample: formatCounterexample, shrink: shrink)
    )
}
