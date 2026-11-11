import HeapModule
import PropertyBased
import PropertyLawKit

/// Checks the `Heap` laws over values drawn from `generator`.
///
/// Draining a heap from either end must agree with sorting its elements, `min` and `max`
/// must bound the contents, and inserting a duplicate of the minimum must pop an equal
/// value. `Heap` is not a `Sequence`, so these are model-based laws.
///
/// - Parameters:
///   - generator: The values to check the laws against.
///   - options: The budget, enforcement and suppressions for the run.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkHeapPropertyLaws<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: Heap<Element>.Type = Heap<Element>.self,
    using generator: Generator<Heap<Element>, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkDrainMinYieldsSortedAscending(generator: generator, options: options),
            await checkDrainMaxYieldsSortedDescending(generator: generator, options: options),
            await checkMinMaxAreUnorderedBounds(generator: generator, options: options),
            await checkInsertDuplicateMinPopsEqual(generator: generator, options: options),
        ]
    }
}

private func checkDrainMinYieldsSortedAscending<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Heap<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Heap.drainMinYieldsSortedAscending",
        generator: generator,
        options: options,
        property: { heap in drainAscending(heap) == heap.unordered.sorted() },
        formatCounterexample: { heap, _ in
            "elements = \(heap.unordered); popMin drain = "
                + "\(drainAscending(heap)), expected \(heap.unordered.sorted())"
        }
    )
}

private func checkDrainMaxYieldsSortedDescending<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Heap<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Heap.drainMaxYieldsSortedDescending",
        generator: generator,
        options: options,
        property: { heap in drainDescending(heap) == heap.unordered.sorted(by: >) },
        formatCounterexample: { heap, _ in
            "elements = \(heap.unordered); popMax drain = "
                + "\(drainDescending(heap)), expected \(heap.unordered.sorted(by: >))"
        }
    )
}

private func checkMinMaxAreUnorderedBounds<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Heap<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Heap.minMaxAreUnorderedBounds",
        generator: generator,
        options: options,
        property: { heap in
            heap.min == heap.unordered.min() && heap.max == heap.unordered.max()
        },
        formatCounterexample: { heap, _ in
            "elements = \(heap.unordered); min = \(String(describing: heap.min)), "
                + "max = \(String(describing: heap.max))"
        }
    )
}

private func checkInsertDuplicateMinPopsEqual<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Heap<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Heap.insertDuplicateMinPopsEqual",
        generator: generator,
        options: options,
        property: { heap in
            guard let currentMin = heap.min else { return true }
            var copy = heap
            copy.insert(currentMin)
            return copy.popMin() == currentMin
        },
        formatCounterexample: { heap, _ in
            "elements = \(heap.unordered); inserting a duplicate of "
                + "min \(String(describing: heap.min)) then popMin() "
                + "did not return an equal value"
        }
    )
}

private func drainAscending<Element: Comparable>(_ heap: Heap<Element>) -> [Element] {
    var copy = heap
    var drained: [Element] = []
    drained.reserveCapacity(copy.count)
    while let minimum = copy.popMin() { drained.append(minimum) }
    return drained
}

private func drainDescending<Element: Comparable>(_ heap: Heap<Element>) -> [Element] {
    var copy = heap
    var drained: [Element] = []
    drained.reserveCapacity(copy.count)
    while let maximum = copy.popMax() { drained.append(maximum) }
    return drained
}
