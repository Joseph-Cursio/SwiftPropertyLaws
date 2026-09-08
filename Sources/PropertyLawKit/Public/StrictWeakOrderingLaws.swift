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
    try await runPropertyLawSuite(options: options) {
        [
            await checkIrreflexivity(generator, compare, options),
            await checkAsymmetry(generator, compare, options),
            await checkOrderTransitivity(generator, compare, options),
            await checkIncomparabilityTransitivity(generator, compare, options)
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
    let applications = Applications()
    return try await runPropertyLawSuite(options: options) {
        [
            await requiringApplicableCases(await runBinaryLaw(
                "StrictWeakOrdering.discrimination",
                tier: .conventional,
                generator: generator,
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
    let applications = Applications()
    return try await runPropertyLawSuite(options: options) {
        [
            await requiringApplicableCases(await runTernaryLaw(
                "StrictWeakOrdering.congruence",
                tier: .conventional,
                generator: generator,
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

// MARK: - The vacuity guard

/// Counts how often a conditional law's antecedent held.
///
/// Four of the six laws here are conditional — `guard compare(a, b), compare(b, c)`,
/// `guard first == second`, and so on — and **a conditional law whose antecedent
/// never fires reports `.passed` having tested nothing.** That is not a
/// hypothetical: `congruence` needs the generator to produce two equal values,
/// which over a wide domain is close to never, so the law goes green for free on
/// exactly the callers most likely to need it.
///
/// This is the same fault `checkInvariantIsFalsifiable` exists to catch, one
/// level down: there the *invariant* forbids nothing, here the *law* applies to
/// nothing. Both are specifications that cannot fail.
private final class Applications: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func record() { lock.lock(); count += 1; lock.unlock() }
    var count_: Int { lock.lock(); defer { lock.unlock() }; return count }
}

/// Turn a vacuous pass into a reported failure.
///
/// Conventional tier: a generator too narrow to produce a qualifying case is
/// outside the law's control, so this reports rather than throws — the caller
/// widens the generator, or passes `.strict` to make it fail the build.
private func requiringApplicableCases(
    _ result: CheckResult,
    _ applications: Applications,
    needing description: String
) -> CheckResult {
    guard case .passed = result.outcome, applications.count_ == 0 else { return result }
    return CheckResult(
        protocolLaw: result.protocolLaw,
        tier: .conventional,
        trials: result.trials,
        seed: result.seed,
        environment: result.environment,
        outcome: .failed(counterexample: """
            vacuous: across \(result.trials) trials the generator never produced \
            \(description), so this law was never applied and its pass means nothing. \
            Widen the generator, or narrow the domain so the case is reachable.
            """),
        nearMisses: result.nearMisses,
        coverageHints: result.coverageHints,
        shrunkFrom: result.shrunkFrom,
        shrinkSteps: result.shrinkSteps
    )
}

// MARK: - The four laws

private func checkIrreflexivity<Value: Sendable, Shrinker: SendableSequenceType>(
    _ generator: Generator<Value, Shrinker>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "StrictWeakOrdering.irreflexivity",
        generator: generator,
        options: options,
        property: { sample in !compare(sample, sample) },
        formatCounterexample: { sample, _ in
            "x = \(sample); compare(x, x) is true, so x sorts before itself"
        }
    )
}

private func checkAsymmetry<Value: Sendable, Shrinker: SendableSequenceType>(
    _ generator: Generator<Value, Shrinker>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "StrictWeakOrdering.asymmetry",
        generator: generator,
        options: options,
        property: { first, second in
            !(compare(first, second) && compare(second, first))
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); each compares before the other"
        }
    )
}

private func checkOrderTransitivity<Value: Sendable, Shrinker: SendableSequenceType>(
    _ generator: Generator<Value, Shrinker>,
    _ compare: @escaping @Sendable (Value, Value) -> Bool,
    _ options: LawCheckOptions
) async -> CheckResult {
    let applications = Applications()
    return await requiringApplicableCases(await runTernaryLaw(
        "StrictWeakOrdering.transitivity",
        generator: generator,
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

private func checkIncomparabilityTransitivity<Value: Sendable, Shrinker: SendableSequenceType>(
    _ generator: Generator<Value, Shrinker>,
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
    return await runTernaryLaw(
        "StrictWeakOrdering.incomparabilityTransitivity",
        generator: generator,
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
