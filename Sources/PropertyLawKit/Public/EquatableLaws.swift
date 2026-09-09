import PropertyBased

/// Run the four `Equatable` protocol laws over `Value` (PRD §4.3).
///
/// All four laws are Strict tier — a violation is a bug. Equatable has no
/// inherited protocol law suite, so `LawSelection` is not exposed here.
///
/// **Coverage hints (M5).** Optional `coverage:` classifier populates
/// `CheckResult.coverageHints` on `Equatable.reflexivity` (the only
/// unary-input law in this suite). Pair / triple-input laws (symmetry,
/// transitivity, negationConsistency) silently ignore the classifier.
@discardableResult
public func checkEquatablePropertyLaws<Value: Equatable & Sendable, Shrinker: SendableSequenceType>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    coverage: AnyCoverageClassifier<Value>? = nil,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async throws -> [CheckResult] {
    try await checkEquatablePropertyLaws(
        from: .sampling(generator), options: options, coverage: coverage, shrink: shrink)
}

/// The same four laws over **every case** of a bounded carrier.
///
/// `Equatable.transitivity` is conditional — it says nothing until three drawn
/// values satisfy `x == y && y == z` — and that antecedent is rare under any
/// generator wide enough to be realistic. Measured on a type whose `==` is
/// "within 1": over 1 000 trials the chain fires 80 times from a 4-value domain,
/// once from 16 values, and **not at all** from 100. A genuinely non-transitive
/// `==` therefore goes undetected at 0...200 on every seed tried, with the suite
/// reporting a clean pass.
///
/// Walking a carrier removes the luck: every pair and every triple of it are
/// present by construction, so the law applies rather than hoping to. The
/// carrier is the explicit choice a narrow generator was making silently, and
/// the result reports how much of it was covered.
///
/// `coverage:` and `shrink:` are absent. Near-miss classification is a sampled
/// concern, and a walk needs no shrinker: ordered smallest-first, the first
/// failure is already the smallest.
@discardableResult
public func checkEquatablePropertyLaws<Value: Equatable & Sendable>(
    for type: Value.Type = Value.self,
    overEvery carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkEquatablePropertyLaws(from: .enumerated(carrier), options: options)
}

/// Random draws from a bounded carrier, keeping the index — for a carrier too
/// large to walk. Failures still shrink toward the smallest case and the run
/// still reports a denominator.
@discardableResult
public func checkEquatablePropertyLaws<Value: Equatable & Sendable>(
    for type: Value.Type = Value.self,
    sampling carrier: Enumeration<Value>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkEquatablePropertyLaws(from: .sampledFromSpace(carrier), options: options)
}

/// One assembler, three sources — so no traversal can run a different set of
/// laws from another.
func checkEquatablePropertyLaws<Value: Equatable & Sendable>(
    from source: InputSource<Value>,
    options: LawCheckOptions,
    coverage: AnyCoverageClassifier<Value>? = nil,
    shrink: (@Sendable (Value) -> [Value])? = nil
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkReflexivity(source: source, options: options, coverage: coverage, shrink: shrink),
            await checkSymmetry(source: source, options: options, shrink: shrink),
            await checkTransitivity(source: source, options: options, shrink: shrink),
            await checkNegationConsistency(source: source, options: options, shrink: shrink)
        ]
    }
}

private func checkReflexivity<Value: Equatable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions,
    coverage: AnyCoverageClassifier<Value>?,
    shrink: (@Sendable (Value) -> [Value])?
) async -> CheckResult {
    let classify: (@Sendable (Value) -> (classes: Set<String>, boundaries: Set<String>))?
    if let coverage {
        classify = { coverage.classify($0) }
    } else {
        classify = nil
    }
    return await runUnaryLaw(
        "Equatable.reflexivity",
        source: source,
        options: options,
        observation: PerLawDriver.Observation(classify: classify),
        property: { sample in sample == sample },
        formatCounterexample: { sample, _ in
            "x = \(sample); x == x evaluated to false"
        },
        shrink: shrink
    )
}

private func checkSymmetry<Value: Equatable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions,
    shrink: (@Sendable (Value) -> [Value])?
) async -> CheckResult {
    await runBinaryLaw(
        "Equatable.symmetry",
        source: source,
        options: options,
        property: { first, second in
            (first == second) == (second == first)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x == y → \(first == second), y == x → \(second == first)"
        },
        shrink: shrink
    )
}

private func checkTransitivity<Value: Equatable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions,
    shrink: (@Sendable (Value) -> [Value])?
) async -> CheckResult {
    let applications = Applications()
    return await requiringApplicableCases(await runTernaryLaw(
        "Equatable.transitivity",
        source: source,
        options: options,
        property: { first, second, third in
            guard first == second, second == third else { return true }
            applications.record()
            return first == third
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); "
                + "x == y and y == z but x != z"
        },
        shrink: shrink
    ), applications, needing: "a chain x == y == z", tier: .heuristic)
}

// Defensive coverage. `!=` is dispatched through Equatable's protocol witness
// as `!(lhs == rhs)`, so this law is structurally unviolable for any Value
// whose `==` is observed through generic dispatch. The check stays in case a
// future Swift change makes `!=` independently overridable; today it always
// passes.
private func checkNegationConsistency<Value: Equatable & Sendable>(
    source: InputSource<Value>,
    options: LawCheckOptions,
    shrink: (@Sendable (Value) -> [Value])?
) async -> CheckResult {
    await runBinaryLaw(
        "Equatable.negationConsistency",
        source: source,
        options: options,
        property: { first, second in
            (first != second) == !(first == second)
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); "
                + "x != y → \(first != second), !(x == y) → \(!(first == second))"
        },
        shrink: shrink
    )
}
