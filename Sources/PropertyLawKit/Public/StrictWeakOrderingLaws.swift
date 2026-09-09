import Foundation
import PropertyBased

/// Run the strict-weak-ordering laws over a **supplied comparator**, the
/// `(T, T) -> Bool` that `sorted(by:)`, `min(by:)` and `max(by:)` take.
///
/// Every other ordering suite in this kit is about a *type's* `Comparable`
/// conformance. This one is about a *function*, and the two are not the same
/// subject: a comparator need not be a type's `<`, is frequently a two-key
/// lexicographic order written inline at a call site, and has no conformance
/// anywhere for `checkComparablePropertyLaws` to check.
///
/// ## Four laws, and what they do not cover
///
/// - `irreflexivity` — `!compare(a, a)`
/// - `asymmetry` — `compare(a, b)` implies `!compare(b, a)`
/// - `transitivity` — `compare(a, b) && compare(b, c)` implies `compare(a, c)`
/// - `incomparabilityTransitivity` — if `a` and `b` are incomparable and `b`
///   and `c` are incomparable, then `a` and `c` are. This is what makes
///   incomparability an equivalence relation, and it is the law hand-written
///   comparators break most often.
///
/// **A comparator can satisfy all four and still sort nondeterministically**,
/// and that is not a defect in these laws. Incomparability is legal: it means
/// *equivalent*. A comparator keyed on `line` alone, ignoring `column`, is a
/// perfectly good strict weak ordering whose equivalence classes happen to
/// contain elements the author wanted ordered — and because `sorted(by:)` is
/// not guaranteed stable in Swift, their relative order is unspecified.
///
/// That was a real defect in SwiftInferProperties: five sort comparators each
/// stopped at `line`, and two declarations sharing one compared equivalent.
/// **These four laws would have passed it.** The law that catches it is
/// `checkComparatorDiscriminates`, deliberately separate — see its own
/// documentation for why it is not part of this suite.
@discardableResult
public func checkStrictWeakOrderingLaws<
    Value: Sendable,
    Shrinker: SendableSequenceType
>(
    over generator: Generator<Value, Shrinker>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkStrictWeakOrderingLaws(from: .sampling(generator), by: compare, options: options)
}

/// The same four laws over **every case** of a bounded carrier.
///
/// Three of the four are conditional — asymmetry needs an ordered pair,
/// transitivity a chain `x < y < z`, incomparability transitivity two
/// incomparable pairs that share a value — and sampling reaches those
/// antecedents only by luck. A comparator with sparse chains can pass
/// `transitivity` a hundred times having never applied it once, and the vacuity
/// guard's report ("the generator never produced …") is then true but
/// unactionable, because widening the generator is not always possible.
///
/// Walking removes the luck. Over a complete walk the antecedent either occurs
/// or **cannot** occur, and the guard says which — see
/// ``Applications/verdict(coverage:)``.
@discardableResult
public func checkStrictWeakOrderingLaws<Value: Sendable>(
    overEvery carrier: Enumeration<Value>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkStrictWeakOrderingLaws(from: .enumerated(carrier), by: compare, options: options)
}

/// One assembler, two sources — so the walked form can never run a different
/// set of laws from the sampled one.
private func checkStrictWeakOrderingLaws<Value: Sendable>(
    from source: InputSource<Value>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkIrreflexivity(source, compare, options),
            await checkAsymmetry(source, compare, options),
            await checkOrderTransitivity(source, compare, options),
            await checkIncomparabilityTransitivity(source, compare, options)
        ]
    }
}

/// Whether the comparator orders **every pair of distinct values** — that no
/// two distinct inputs are incomparable.
///
/// Separate from `checkStrictWeakOrderingLaws` on purpose, and not part of it,
/// because a comparator over a deliberately lossy key is *supposed* to have
/// equivalence classes: grouping by category, bucketing by day, ranking by
/// score with ties intended. Folding this into the suite would report those as
/// failures, and they are the point.
///
/// Ask for it where the comparator's job is a **reproducible order** — anything
/// whose output is written to a file, compared between runs, or rendered for a
/// human. Those comparators usually say so in prose: *"then by name ascending
/// for stability across runs."* This is that sentence, checkable.
///
/// Conventional rather than Strict: a generator too narrow to produce two
/// distinct values that collide cannot demonstrate the property, and that is
/// outside the caller's control.
///
/// `distinct` decides which pairs the law applies to. It defaults to `!=` where
/// `Value` is `Equatable`; supply your own where identity means something
/// narrower than equality.
@discardableResult
public func checkComparatorDiscriminates<
    Value: Sendable,
    Shrinker: SendableSequenceType
>(
    over generator: Generator<Value, Shrinker>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    distinct: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkComparatorDiscriminates(
        from: .sampling(generator), by: compare, distinct: distinct, options: options)
}

/// Discrimination over **every pair** of a bounded carrier. A sampled run that
/// never draws two distinct values reports a vacuous pass; a walk either finds
/// such a pair or proves the carrier holds none.
@discardableResult
public func checkComparatorDiscriminates<Value: Sendable>(
    overEvery carrier: Enumeration<Value>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    distinct: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkComparatorDiscriminates(
        from: .enumerated(carrier), by: compare, distinct: distinct, options: options)
}

private func checkComparatorDiscriminates<Value: Sendable>(
    from source: InputSource<Value>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    distinct: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions
) async throws -> [CheckResult] {
    let applications = Applications()
    return try await runPropertyLawSuite(options: options) {
        [
            await requiringApplicableCases(await runBinaryLaw(
                "StrictWeakOrdering.discrimination",
                tier: .conventional,
                source: source,
                options: options,
                property: { first, second in
                    guard distinct(first, second) else { return true }
                    applications.record()
                    return compare(first, second) || compare(second, first)
                },
                formatCounterexample: { first, second, _ in
                    """
                    x = \(first), y = \(second); the two are distinct and neither \
                    orders before the other, so their relative order after a sort \
                    is unspecified — `sorted(by:)` is not guaranteed stable.
                    """
                }
            ), applications, needing: "two distinct values")
        ]
    }
}

/// Whether the comparator is a function of the **value** rather than of the
/// **storage** — that equal inputs compare identically against everything.
///
/// ```
/// a == b  ⇒  compare(a, x) == compare(b, x)   for all x
/// ```
///
/// Separate from the suite because a type whose `==` carries no meaning cannot
/// state it, and separate from `checkComparatorDiscriminates` because it is a
/// different question. It is also the law that makes discrimination
/// *well-defined*: that law quantifies over distinct values, meaning
/// equivalence classes under `==`, and if a comparator can order two members of
/// one class differently then the classes are not the unit being reasoned
/// about — the law would pass or fail depending on which copy the generator
/// happened to produce.
///
/// **Copy-on-write is what makes this reachable by accident.** A value and its
/// copy are indistinguishable by `==` and distinguishable by storage identity,
/// and a comparator can see both. Reading an `ObjectIdentifier` of a boxed
/// payload, a token minted per buffer, or a cached value that survives a copy
/// all break this while leaving the four ordering laws intact.
///
/// Conventional rather than Strict: a generator that never produces two equal
/// values cannot demonstrate the property, which is outside the caller's
/// control.
@discardableResult
public func checkComparatorIsCongruent<
    Value: Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    over generator: Generator<Value, Shrinker>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkComparatorIsCongruent(from: .sampling(generator), by: compare, options: options)
}

/// Congruence over **every triple** of a bounded carrier. This law needs two
/// values that are `==` and not identical, which a wide generator produces
/// close to never — so it is the law most likely to go green having tested
/// nothing, and the one that gains most from being walked.
@discardableResult
public func checkComparatorIsCongruent<Value: Equatable & Sendable>(
    overEvery carrier: Enumeration<Value>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await checkComparatorIsCongruent(from: .enumerated(carrier), by: compare, options: options)
}

private func checkComparatorIsCongruent<Value: Equatable & Sendable>(
    from source: InputSource<Value>,
    by compare: @escaping @Sendable (Value, Value) -> Bool,
    options: LawCheckOptions
) async throws -> [CheckResult] {
    let applications = Applications()
    return try await runPropertyLawSuite(options: options) {
        [
            await requiringApplicableCases(await runTernaryLaw(
                "StrictWeakOrdering.congruence",
                tier: .conventional,
                source: source,
                options: options,
                property: { first, second, probe in
                    guard first == second else { return true }
                    applications.record()
                    return compare(first, probe) == compare(second, probe)
                        && compare(probe, first) == compare(probe, second)
                },
                formatCounterexample: { first, second, probe, _ in
                    """
                    x = \(first), y = \(second), probe = \(probe); x == y but they \
                    compare differently against the probe, so the comparator reads \
                    something `==` does not — storage identity is the usual cause.
                    """
                }
            ), applications, needing: "two values that are equal but not identical")
        ]
    }
}

private func checkIrreflexivity<Value: Sendable>(
    _ source: InputSource<Value>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StrictWeakOrdering.irreflexivity",
        source: source,
        options: options,
        property: { sample in !compare(sample, sample) },
        formatCounterexample: { sample, _ in
            "x = \(sample); compare(x, x) is true, so x sorts before itself"
        }
    )
}

private func checkAsymmetry<Value: Sendable>(
    _ source: InputSource<Value>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "StrictWeakOrdering.asymmetry",
        source: source,
        options: options,
        property: { first, second in
            !(compare(first, second) && compare(second, first))
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); each compares before the other"
        }
    )
}

private func checkOrderTransitivity<Value: Sendable>(
    _ source: InputSource<Value>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    let applications = Applications()
    return await requiringApplicableCases(await runTernaryLaw(
        "StrictWeakOrdering.transitivity",
        source: source,
        options: options,
        property: { first, second, third in
            guard compare(first, second), compare(second, third) else { return true }
            applications.record()
            return compare(first, third)
        },
        formatCounterexample: { first, second, third, _ in
            "x = \(first), y = \(second), z = \(third); x < y and y < z but not x < z"
        }
    ), applications, needing: "a chain x < y < z")
}

private func checkIncomparabilityTransitivity<Value: Sendable>(
    _ source: InputSource<Value>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    let incomparable: @Sendable (Value, Value) -> Bool = { lhs, rhs in
        !compare(lhs, rhs) && !compare(rhs, lhs)
    }
    // No vacuity guard here, deliberately. A comparator that orders every pair —
    // which is what `checkComparatorDiscriminates` asks for — has no incomparable
    // pairs at all, so this law is vacuous *by construction* on exactly the
    // comparators most likely to be correct. Guarding it would report the good
    // case as a defect. The other three conditional laws have no such reading:
    // no chains, no distinct pairs and no equal pairs are all generator
    // weaknesses rather than properties worth having.
    //
    // **Walking the carrier does not change this, and that is the asymmetry
    // worth noticing.** For the other three, a complete walk converts an
    // ambiguous silence into a fact, so the guard gets sharper. Here the fact it
    // would establish — "no two cases in this carrier are incomparable" — is the
    // definition of a total order, which is a result rather than a defect. So
    // vacuity detection is a property of the *law*, not of the harness, and no
    // amount of coverage makes it uniform.
    return await runTernaryLaw(
        "StrictWeakOrdering.incomparabilityTransitivity",
        source: source,
        options: options,
        property: { first, second, third in
            guard incomparable(first, second), incomparable(second, third) else { return true }
            return incomparable(first, third)
        },
        formatCounterexample: { first, second, third, _ in
            """
            x = \(first), y = \(second), z = \(third); x and y are equivalent and \
            y and z are equivalent, but x and z are not — so equivalence is not \
            transitive and this is not a strict weak ordering.
            """
        }
    )
}
