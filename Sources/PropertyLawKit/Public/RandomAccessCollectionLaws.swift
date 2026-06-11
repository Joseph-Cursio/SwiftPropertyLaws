import PropertyBased

/// Run `RandomAccessCollection` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `BidirectionalCollection` suite
/// first (which itself chains `Collection`, `Sequence`, and
/// `IteratorProtocol`); `.ownOnly` skips inherited laws.
///
/// RandomAccessCollection laws (all Strict) — these check value equivalence
/// of the random-access methods against walking via `index(after:)` /
/// `index(before:)`. Performance (the O(1) part of the contract) isn't
/// measured; only the *answer* the methods give:
/// - `distanceConsistency` — `distance(from: i, to: j)` equals the signed
///   number of `index(after:)` steps from `i` to `j`.
/// - `offsetConsistency` — `index(i, offsetBy: n)` equals the index reached
///   by walking `n` forward (or `-n` backward) steps from `i`.
/// - `negativeOffsetInversion` — `index(index(i, offsetBy: n), offsetBy: -n)
///   == i` for any `n` keeping both indices in range.
@discardableResult
public func checkRandomAccessCollectionPropertyLaws<
    Value: RandomAccessCollection & Sendable,
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
                try await checkBidirectionalCollectionPropertyLaws(
                    for: type,
                    using: generator,
                    options: $0,
                    sequenceOptions: sequenceOptions
                )
            })
        }
        results.append(contentsOf: [
            await checkDistanceConsistency(generator: generator, options: options),
            await checkOffsetConsistency(generator: generator, options: options),
            await checkNegativeOffsetInversion(generator: generator, options: options)
        ])
        return results
    }
}

private func checkDistanceConsistency<
    C: RandomAccessCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "RandomAccessCollection.distanceConsistency",
        generator: generator,
        options: options,
        property: { sample in distanceConsistencyCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            distanceConsistencyCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

private func checkOffsetConsistency<
    C: RandomAccessCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "RandomAccessCollection.offsetConsistency",
        generator: generator,
        options: options,
        property: { sample in offsetConsistencyCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            offsetConsistencyCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

private func checkNegativeOffsetInversion<
    C: RandomAccessCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "RandomAccessCollection.negativeOffsetInversion",
        generator: generator,
        options: options,
        property: { sample in negativeOffsetInversionCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            negativeOffsetInversionCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

/// All valid indices including `endIndex` — every index ever passed to a
/// random-access method belongs to this set, so the laws sweep this set
/// against the method's value answer.
private func walkedIndices<C: Collection>(of sample: C) -> [C.Index] {
    var indices: [C.Index] = []
    var idx = sample.startIndex
    let cap = (sample.count &+ 1) &* 2
    var steps = 0
    while idx != sample.endIndex {
        if steps > cap { break }
        indices.append(idx)
        idx = sample.index(after: idx)
        steps += 1
    }
    indices.append(sample.endIndex)
    return indices
}

private func distanceConsistencyCounterexample<C: RandomAccessCollection>(
    for sample: C
) -> String? {
    let indices = walkedIndices(of: sample)
    for (iPos, iIdx) in indices.enumerated() {
        for (jPos, jIdx) in indices.enumerated() {
            let reported = sample.distance(from: iIdx, to: jIdx)
            let expected = jPos - iPos
            if reported != expected {
                return "distance(from: idx[\(iPos)], to: idx[\(jPos)]) on "
                    + "\(sample) = \(reported), expected \(expected) "
                    + "(walked via index(after:))"
            }
        }
    }
    return nil
}

private func offsetConsistencyCounterexample<C: RandomAccessCollection>(
    for sample: C
) -> String? {
    let indices = walkedIndices(of: sample)
    let lastValidPosition = indices.count - 1
    for (iPos, iIdx) in indices.enumerated() {
        for offset in -iPos...(lastValidPosition - iPos) {
            let reported = sample.index(iIdx, offsetBy: offset)
            let expected = indices[iPos + offset]
            if reported != expected {
                return "index(idx[\(iPos)], offsetBy: \(offset)) on \(sample) "
                    + "= \(reported), expected idx[\(iPos + offset)]"
            }
        }
    }
    return nil
}

private func negativeOffsetInversionCounterexample<C: RandomAccessCollection>(
    for sample: C
) -> String? {
    let indices = walkedIndices(of: sample)
    let lastValidPosition = indices.count - 1
    for (iPos, iIdx) in indices.enumerated() {
        for offset in -iPos...(lastValidPosition - iPos) {
            let advanced = sample.index(iIdx, offsetBy: offset)
            let inverted = sample.index(advanced, offsetBy: -offset)
            if inverted != iIdx {
                return "index(idx[\(iPos)], offsetBy: \(offset)) then "
                    + "offsetBy(\(-offset)) on \(sample) yielded \(inverted), "
                    + "expected idx[\(iPos)]"
            }
        }
    }
    return nil
}
