import OrderedCollections
import PropertyBased
import PropertyLawKit

/// Checks the `OrderedSet` order-preservation laws over values drawn from `generator`.
///
/// Appending an existing member must not move it, a union must keep the left operand's
/// order and append the right operand's new members, and a union must agree with its
/// mirror image on membership.
///
/// - Parameters:
///   - generator: The values to check the laws against.
///   - options: The budget, enforcement and suppressions for the run.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkOrderPreservationPropertyLaws<
    Element: Hashable & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: OrderedSet<Element>.Type = OrderedSet<Element>.self,
    using generator: Generator<OrderedSet<Element>, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkAppendExistingPreservesOrder(generator: generator, options: options),
            await checkUnionKeepsLeftOrderThenNovelRight(generator: generator, options: options),
            await checkUnionIsMembershipCommutative(generator: generator, options: options),
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
