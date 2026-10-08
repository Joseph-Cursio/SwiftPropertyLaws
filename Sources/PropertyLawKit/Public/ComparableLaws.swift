import PropertyBased

/// Run `Comparable` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Equatable` suite first per PRD
/// §4.3 inheritance semantics; `.ownOnly` skips it.
///
/// Returned-array order: Equatable laws (when `.all`) then Comparable laws —
/// `irreflexivity` (Strict), `antisymmetry` (Strict), `transitivity` (Strict),
/// `totality` (Conventional), `operatorConsistency` (Strict).
@discardableResult
public func checkComparablePropertyLaws<Value: Comparable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkComparablePropertyLaws(from: .sampling(generator), options: options, laws: laws)
}

/// The same laws over **every case** of a bounded carrier.
///
/// `Comparable.antisymmetry` is conditional on `x <= y && y <= x` — two values
/// the order calls equivalent — and a sampled run reaches that only when two
/// independent draws happen to be. An ordering by `abs(cents)` breaks the law
/// for `5` and `-5` and nowhere else, so at ±1 000 000 it passes on essentially
/// every seed. Walking `-3 ... 3` finds it, because every pair of the carrier is
/// present by construction — and the inherited `Equatable` laws, which need
/// equal values the same way, are walked too.
///
/// `Equatable` and `Hashable` have had this entry since the rare-antecedent
/// work; `Comparable` is the third protocol whose laws need equal values.
@discardableResult
public func checkComparablePropertyLaws<Value: Comparable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult] {
    try await checkComparablePropertyLaws(from: .enumerated(carrier), options: options, laws: laws)
}

/// One assembler, two sources — so a walked suite cannot run a different set of
/// laws from the sampled one.
func checkComparablePropertyLaws<Value: Comparable & Sendable>(
    from source: InputSource<Value>,
    options: LawCheckOptions,
    laws: LawSelection
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkEquatablePropertyLaws(from: source, options: $0)
            })
        }
        results.append(contentsOf: [
            await checkIrreflexivity(source: source, options: options),
            await checkAntisymmetry(source: source, options: options),
            await checkTransitivity(source: source, options: options),
            await checkTotality(source: source, options: options),
            await checkOperatorConsistency(source: source, options: options)
        ])
        return results
    }
}

// `Comparable` requires `<` to be a strict total order, so `a < a` is always
// false. The other laws here cannot see a `<` written as `<=`: they are all
// stated over *two* values, and that bug shows only when the two are equal —
// which two independent draws from a realistic generator almost never are.
// Measured at ±1 000 000 over 1 000 trials, every other law passes it on
// essentially every seed. Stated over one value, it fails on the first trial.
//
// Holds for IEEE-754 floats too: `NaN < NaN` is false, like every comparison
// with NaN, so no `allowNaN` gate is needed.
private func checkIrreflexivity<Value: Comparable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Comparable.irreflexivity",
        source: source,
        options: options,
        property: { sample in !(sample < sample) },
        formatCounterexample: { sample, _ in
            "x = \(sample); x < x evaluated to true, but `<` must be a strict order "
                + "(is it implemented as `<=`?)"
        }
    )
}

// Conditional on `x <= y && y <= x` — two values the order calls equivalent —
// and so rare under a wide generator that the law can pass having applied to
// nothing: an ordering by `abs(cents)` is antisymmetry's bug exactly, and at
// ±1 000 000 two draws share an absolute value about once in a million pairs.
// The count is reported, not enforced, for the reason `reportingApplications`
// gives.
private func checkAntisymmetry<Value: Comparable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    let applications = Applications()
    return await reportingApplications(applications, of: await runBinaryLaw(
        "Comparable.antisymmetry",
        source: source,
        options: options,
        property: { first, second in
            guard first <= second, second <= first else { return true }
            applications.record()
            return first == second
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); x <= y and y <= x but x != y"
        }
    ))
}

private func checkTransitivity<Value: Comparable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    let applications = Applications()
    return await reportingApplications(applications, of: await runTernaryLaw(
        "Comparable.transitivity",
        source: source,
        options: options,
        property: { first, second, third in
            guard first <= second, second <= third else { return true }
            applications.record()
            return first <= third
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x <= y and y <= z but !(x <= z)"
        }
    ))
}

private func checkTotality<Value: Comparable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Comparable.totality",
        tier: .conventional,
        source: source,
        options: options,
        property: { first, second in
            first <= second || second <= first
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); neither x <= y nor y <= x (NaN-like)"
        }
    )
}

// `<=`, `>`, `>=` are derived from `<` by Comparable's protocol witnesses, so
// this check can't catch "user overrode `<=` inconsistently with `<`" through
// generic dispatch. It DOES catch "user's `<` is broken in a way that makes
// the derived operators internally inconsistent" — e.g. `<` returning true
// for both directions of a pair makes `x < y` and `!(x <= y)` simultaneously
// true.
private func checkOperatorConsistency<Value: Comparable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "Comparable.operatorConsistency",
        source: source,
        options: options,
        property: { first, second in
            operatorConsistencyCounterexample(for: (first, second)) == nil
        },
        formatCounterexample: { first, second, _ in
            operatorConsistencyCounterexample(for: (first, second)) ?? "<no counterexample>"
        }
    )
}

private func operatorConsistencyCounterexample<Value: Comparable>(
    for input: (Value, Value)
) -> String? {
    let (first, second) = input
    let lessThan = first < second
    let greaterThan = first > second
    let lessOrEqual = first <= second
    let greaterOrEqual = first >= second
    if greaterThan != (second < first) {
        return "x = \(first), y = \(second); x > y → \(greaterThan) "
            + "but y < x → \(second < first)"
    }
    if greaterOrEqual != (second <= first) {
        return "x = \(first), y = \(second); x >= y → \(greaterOrEqual) "
            + "but y <= x → \(second <= first)"
    }
    if lessThan && !lessOrEqual {
        return "x = \(first), y = \(second); x < y but !(x <= y)"
    }
    return nil
}
