import HeapModule
import PropertyBased
import PropertyLawKit

/// Laws for `Heap` — the first model-based family in the kit (Phase 1 M3 of
/// the collections/async workplan). `Heap` sits outside the stdlib protocol
/// lattice (not `Sequence`), so instead of protocol-conformance laws it gets
/// oracle laws against the sorted-array model:
///
/// - `drainMinYieldsSortedAscending` — repeatedly `popMin()` until empty
///   yields exactly `unordered.sorted()`.
/// - `drainMaxYieldsSortedDescending` — repeatedly `popMax()` yields exactly
///   `unordered.sorted(by: >)`.
/// - `minMaxAreUnorderedBounds` — `min` / `max` agree with the model's
///   `min()` / `max()`.
/// - `insertDuplicateMinPopsEqual` — inserting a copy of the current
///   minimum, then `popMin()`, returns a value equal to it (vacuous on the
///   empty heap).
///
/// Unlike the protocol families these laws are stated over the concrete
/// `Heap<Element>` (there is no heap protocol to abstract over), so the
/// planted-violator self-test gate doesn't apply — the laws exercise
/// swift-collections itself, not substitutable user conformances.
public enum HeapLaw: String, Sendable, Hashable, CaseIterable {
    case drainMinYieldsSortedAscending
    case drainMaxYieldsSortedDescending
    case minMaxAreUnorderedBounds
    case insertDuplicateMinPopsEqual
}

extension LawIdentifier {
    public static func heap(_ law: HeapLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Heap", lawName: law.rawValue)
    }
}

@discardableResult
public func checkHeapPropertyLaws<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Heap<Element>.Type = Heap<Element>.self,
    using generator: Generator<Heap<Element>, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkDrainMinYieldsSortedAscending(generator: generator, options: options),
            await checkDrainMaxYieldsSortedDescending(generator: generator, options: options),
            await checkMinMaxAreUnorderedBounds(generator: generator, options: options),
            await checkInsertDuplicateMinPopsEqual(generator: generator, options: options)
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
