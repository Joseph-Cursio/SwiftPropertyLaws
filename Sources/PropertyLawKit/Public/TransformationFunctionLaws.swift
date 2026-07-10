import PropertyBased

/// Caller-supplied element functions for the parameterized transformation
/// laws. The kit cannot invent functions over a generic `Element`, so —
/// like `Strideable`'s `strideGenerator:` — the caller names them
/// explicitly: two endomorphisms (`first`, `second`) and a `predicate`.
///
/// Pick functions that actually *move* elements (`{ $0 &* 2 }`, not
/// `{ $0 }`) and a predicate that splits the generated domain; identity
/// functions and constant predicates satisfy the laws vacuously.
public struct TransformationFunctions<Element: Sendable>: Sendable {
    public let first: @Sendable (Element) -> Element
    public let second: @Sendable (Element) -> Element
    public let predicate: @Sendable (Element) -> Bool

    public init(
        first: @escaping @Sendable (Element) -> Element,
        second: @escaping @Sendable (Element) -> Element,
        predicate: @escaping @Sendable (Element) -> Bool
    ) {
        self.first = first
        self.second = second
        self.predicate = predicate
    }
}

/// The parameterized half of the transformation-algebra family (Phase 2 M2
/// of the collections/async workplan). Four Strict-tier laws over
/// caller-supplied functions:
///
/// - `mapFusion` — `x.map(f).map(g) == x.map { g(f($0)) }`
/// - `mapFilterCommutation` — `x.map(f).filter(p) ==
///   x.filter { p(f($0)) }.map(f)` (the always-valid form: filtering after
///   a map equals pre-filtering through the composed predicate)
/// - `lazyMapEquivalence` — `Array(x.lazy.map(f)) == x.map(f)`
/// - `lazyFilterEquivalence` — `Array(x.lazy.filter(p)) == x.filter(p)`
///
/// Same multi-pass assumption as the closure-free half. The laws hold for
/// *pure* functions only — a stateful `first`/`predicate` closure breaks
/// fusion and lazy-equivalence by design (lazy evaluates on demand and
/// possibly repeatedly), which is exactly the teaching point the book's
/// Chapter 2 makes about referential transparency.
@discardableResult
public func checkTransformationPropertyLaws<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    functions: TransformationFunctions<Value.Element>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] where Value.Element: Equatable & Sendable {
    try await runPropertyLawSuite(options: options) {
        [
            await checkMapFusion(generator: generator, functions: functions, options: options),
            await checkMapFilterCommutation(
                generator: generator, functions: functions, options: options
            ),
            await checkLazyMapEquivalence(
                generator: generator, functions: functions, options: options
            ),
            await checkLazyFilterEquivalence(
                generator: generator, functions: functions, options: options
            )
        ]
    }
}

private func checkMapFusion<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    functions: TransformationFunctions<Value.Element>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Equatable & Sendable {
    await runUnaryLaw(
        "Transformation.mapFusion",
        generator: generator,
        options: options,
        property: { sample in
            let stepwise = sample.map(functions.first).map(functions.second)
            let fused = sample.map { functions.second(functions.first($0)) }
            return stepwise == fused
        },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); x.map(f).map(g) != x.map(g ∘ f)"
        }
    )
}

private func checkMapFilterCommutation<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    functions: TransformationFunctions<Value.Element>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Equatable & Sendable {
    await runUnaryLaw(
        "Transformation.mapFilterCommutation",
        generator: generator,
        options: options,
        property: { sample in
            let mapThenFilter = sample.map(functions.first).filter(functions.predicate)
            let filterThenMap = sample
                .filter { functions.predicate(functions.first($0)) }
                .map(functions.first)
            return mapThenFilter == filterThenMap
        },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); x.map(f).filter(p) != x.filter(p ∘ f).map(f)"
        }
    )
}

private func checkLazyMapEquivalence<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    functions: TransformationFunctions<Value.Element>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Equatable & Sendable {
    await runUnaryLaw(
        "Transformation.lazyMapEquivalence",
        generator: generator,
        options: options,
        property: { sample in
            Array(sample.lazy.map(functions.first)) == sample.map(functions.first)
        },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); Array(x.lazy.map(f)) != x.map(f)"
        }
    )
}

private func checkLazyFilterEquivalence<
    Value: Sequence & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Value, Shrinker>,
    functions: TransformationFunctions<Value.Element>,
    options: LawCheckOptions
) async -> CheckResult where Value.Element: Equatable & Sendable {
    await runUnaryLaw(
        "Transformation.lazyFilterEquivalence",
        generator: generator,
        options: options,
        property: { sample in
            Array(sample.lazy.filter(functions.predicate)) == sample.filter(functions.predicate)
        },
        formatCounterexample: { sample, _ in
            "x = \(Array(sample)); Array(x.lazy.filter(p)) != x.filter(p)"
        }
    )
}
