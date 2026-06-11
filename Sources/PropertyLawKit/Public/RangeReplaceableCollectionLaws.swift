import PropertyBased

/// Run `RangeReplaceableCollection` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Collection` suite first;
/// `.ownOnly` skips it.
///
/// RangeReplaceableCollection laws (all Strict). The protocol's two
/// requirements are `init()` and `replaceSubrange(_:with:)`; every other
/// mutating method (`append`, `insert`, `remove(at:)`, `removeAll`, …) is
/// derived from those. The laws exercise the requirements directly plus
/// the most common derived shapes:
/// - `emptyInitIsEmpty` — `Self()` produces an empty collection.
/// - `removeAtInsertRoundTrip` — for any valid position `p`, `remove(at:p)`
///   followed by `insert(removed, at: p)` reproduces the original.
/// - `removeAllMakesEmpty` — `removeAll()` produces an empty collection.
/// - `replaceSubrangeAppliesEdit` — replacing `[startIndex..<endIndex]` with
///   an empty collection clears the range. This catches a no-op
///   `replaceSubrange(_:with:)` — the only mutating requirement of the
///   protocol — that the round-trip and removeAll laws miss (the kit's
///   `removeAll(keepingCapacity:)` default impl bypasses replaceSubrange
///   entirely via `self = Self()`, and a no-op replaceSubrange combined
///   with a no-op `remove(at:)` produces a passing round-trip).
@discardableResult
public func checkRangeReplaceableCollectionPropertyLaws<
    Value: RangeReplaceableCollection & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sequenceOptions: SequenceLawOptions = SequenceLawOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult]
where Value.Element: Equatable & Sendable {
    try await runPropertyLawSuite(options: options) {
        var results: [CheckResult] = []
        if laws == .all {
            results.append(contentsOf: await collectingInheritedLaws(rebasing: options) {
                try await checkCollectionPropertyLaws(
                    for: type,
                    using: generator,
                    options: $0,
                    sequenceOptions: sequenceOptions
                )
            })
        }
        results.append(contentsOf: [
            await checkEmptyInitIsEmpty(generator: generator, options: options),
            await checkRemoveAtInsertRoundTrip(generator: generator, options: options),
            await checkRemoveAllMakesEmpty(generator: generator, options: options),
            await checkReplaceSubrangeAppliesEdit(generator: generator, options: options)
        ])
        return results
    }
}

private func checkEmptyInitIsEmpty<
    C: RangeReplaceableCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "RangeReplaceableCollection.emptyInitIsEmpty",
        generator: generator,
        options: options,
        property: { _ in
            let empty = C()
            return empty.isEmpty
        },
        formatCounterexample: { _, _ in
            "Self() reported isEmpty = \(C().isEmpty), expected true"
        }
    )
}

private func checkRemoveAtInsertRoundTrip<
    C: RangeReplaceableCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "RangeReplaceableCollection.removeAtInsertRoundTrip",
        generator: generator,
        options: options,
        property: { sample in removeInsertCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            removeInsertCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

private func checkRemoveAllMakesEmpty<
    C: RangeReplaceableCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "RangeReplaceableCollection.removeAllMakesEmpty",
        generator: generator,
        options: options,
        property: { sample in
            var copy = sample
            copy.removeAll()
            return copy.isEmpty
        },
        formatCounterexample: { sample, _ in
            var copy = sample
            copy.removeAll()
            return "removeAll() on \(Array(sample.prefix(8)))… left "
                + "\(Array(copy.prefix(8)))…, expected empty"
        }
    )
}

private func checkReplaceSubrangeAppliesEdit<
    C: RangeReplaceableCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "RangeReplaceableCollection.replaceSubrangeAppliesEdit",
        generator: generator,
        options: options,
        property: { sample in
            if sample.isEmpty { return true }
            var copy = sample
            copy.replaceSubrange(
                copy.startIndex..<copy.endIndex,
                with: EmptyCollection<C.Element>()
            )
            return copy.isEmpty
        },
        formatCounterexample: { sample, _ in
            var copy = sample
            copy.replaceSubrange(
                copy.startIndex..<copy.endIndex,
                with: EmptyCollection<C.Element>()
            )
            return "replaceSubrange(0..<count, with: <empty>) on "
                + "\(Array(sample).prefix(8))… left \(Array(copy).prefix(8))…, "
                + "expected empty"
        }
    )
}

private func removeInsertCounterexample<C: RangeReplaceableCollection>(
    for sample: C
) -> String?
where C.Element: Equatable {
    let originalSnapshot = Array(sample)
    let count = originalSnapshot.count
    if count == 0 { return nil }
    for position in 0..<count {
        var copy = sample
        let removeIdx = copy.index(copy.startIndex, offsetBy: position)
        let removed = copy.remove(at: removeIdx)
        let insertIdx = copy.index(copy.startIndex, offsetBy: position)
        copy.insert(removed, at: insertIdx)
        let after = Array(copy)
        if after != originalSnapshot {
            return "remove(at: pos \(position)) + insert at pos \(position) "
                + "on \(originalSnapshot.prefix(8))… yielded "
                + "\(after.prefix(8))…"
        }
    }
    return nil
}
