import OrderedCollections
import PropertyBased
import PropertyLawKit

/// Laws for `OrderedSet`'s defining behavior — insertion-order preservation
/// (Phase 1 M3 of the collections/async workplan). `OrderedSet` deliberately
/// isn't `SetAlgebra` because its set operations are order-asymmetric; these
/// laws pin down exactly that asymmetry instead of pretending it away:
///
/// - `appendExistingPreservesOrder` — re-appending every element the set
///   already contains reports `inserted == false` each time and leaves the
///   set (including order) unchanged.
/// - `unionKeepsLeftOrderThenNovelRight` — `x.union(y)` is exactly `x`'s
///   elements in `x`'s order followed by `y`'s novel elements in `y`'s
///   order. This *is* the order-sensitivity of union, stated as a total
///   deterministic definition rather than an inequality.
/// - `unionIsMembershipCommutative` — under membership equality
///   (`Set(_:)` projection), union commutes after all.
///
/// The last two are a metamorphic pair: the same operation commutes under
/// the coarser equivalence and is order-defined under the finer one —
/// the "commutative under *which* equality?" lesson, executable.
public enum OrderPreservationLaw: String, Sendable, Hashable, CaseIterable {
    case appendExistingPreservesOrder
    case unionKeepsLeftOrderThenNovelRight
    case unionIsMembershipCommutative
}

extension LawIdentifier {
    public static func orderPreservation(_ law: OrderPreservationLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "OrderedSet", lawName: law.rawValue)
    }
}

@discardableResult
public func checkOrderPreservationPropertyLaws<
    Element: Hashable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: OrderedSet<Element>.Type = OrderedSet<Element>.self,
    using generator: Generator<OrderedSet<Element>, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkAppendExistingPreservesOrder(generator: generator, options: options),
            await checkUnionKeepsLeftOrderThenNovelRight(generator: generator, options: options),
            await checkUnionIsMembershipCommutative(generator: generator, options: options)
        ]
    }
}

private func checkAppendExistingPreservesOrder<
    Element: Hashable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<OrderedSet<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "OrderedSet.appendExistingPreservesOrder",
        generator: generator,
        options: options,
        property: { set in
            var copy = set
            for element in set where copy.append(element).inserted {
                return false
            }
            return copy == set
        },
        formatCounterexample: { set, _ in
            "set = \(set); re-appending an existing element either reported "
                + "inserted == true or changed the set's order"
        }
    )
}

private func checkUnionKeepsLeftOrderThenNovelRight<
    Element: Hashable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<OrderedSet<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "OrderedSet.unionKeepsLeftOrderThenNovelRight",
        generator: generator,
        options: options,
        property: { first, second in
            let expected = Array(first) + second.filter { first.contains($0) == false }
            return Array(first.union(second)) == expected
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); x.union(y) = \(first.union(second)), "
                + "expected x's order then y's novel elements = "
                + "\(Array(first) + second.filter { first.contains($0) == false })"
        }
    )
}

private func checkUnionIsMembershipCommutative<
    Element: Hashable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<OrderedSet<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "OrderedSet.unionIsMembershipCommutative",
        generator: generator,
        options: options,
        property: { first, second in
            Set(first.union(second)) == Set(second.union(first))
        },
        formatCounterexample: { first, second, _ in
            "x = \(first), y = \(second); Set(x ∪ y) = \(Set(first.union(second))), "
                + "Set(y ∪ x) = \(Set(second.union(first)))"
        }
    )
}
