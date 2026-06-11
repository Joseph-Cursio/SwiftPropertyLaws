import PropertyBased

/// Run `MutableCollection` protocol laws over `Value` (PRD §4.3).
///
/// Default `laws: .all` runs the inherited `Collection` suite first;
/// `.ownOnly` skips it.
///
/// MutableCollection laws (all Strict). The contract is that a value
/// written through the subscript setter is observable through the getter
/// at the same index, without disturbing other elements. The laws exercise
/// this contract through `swapAt(_:_:)` (whose default implementation goes
/// through subscript get + set):
/// - `swapAtSwapsValues` — after `c.swapAt(i, j)`, `c[i] == sample[j]` and
///   `c[j] == sample[i]`. Catches setters that drop writes (no-op), invert
///   the assigned value, or write to the wrong index.
/// - `swapAtInvolution` — `swapAt(i, j)` twice equals identity. Catches
///   setters that *transform* the assigned value (e.g. doubling, clamping),
///   which `swapAtSwapsValues` would also catch but a value-transform bug
///   surfaces here in a clean involution form.
@discardableResult
public func checkMutableCollectionPropertyLaws<
    Value: MutableCollection & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    options: LawCheckOptions = LawCheckOptions(),
    sequenceOptions: SequenceLawOptions = SequenceLawOptions(),
    laws: LawSelection = .all
) async throws -> [CheckResult]
where Value.Element: Equatable & Sendable {
    try ReplayEnvironmentValidator.verify(options)
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
        await checkSwapAtSwapsValues(generator: generator, options: options),
        await checkSwapAtInvolution(generator: generator, options: options)
    ])
    try PropertyLawViolation.throwIfViolations(in: results, enforcement: options.enforcement)
    return results
}

private func checkSwapAtSwapsValues<
    C: MutableCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "MutableCollection.swapAtSwapsValues",
        generator: generator,
        options: options,
        property: { sample in swapAtSwapsValuesCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            swapAtSwapsValuesCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

private func checkSwapAtInvolution<
    C: MutableCollection & Sendable,
    Sh: SendableSequenceType
>(
    generator: Generator<C, Sh>,
    options: LawCheckOptions
) async -> CheckResult
where C.Element: Equatable & Sendable {
    await runUnaryLaw(
        "MutableCollection.swapAtInvolution",
        generator: generator,
        options: options,
        property: { sample in swapAtInvolutionCounterexample(for: sample) == nil },
        formatCounterexample: { sample, _ in
            swapAtInvolutionCounterexample(for: sample) ?? "<no counterexample>"
        }
    )
}

private func swapAtSwapsValuesCounterexample<C: MutableCollection>(
    for sample: C
) -> String?
where C.Element: Equatable {
    let indices = mutableCollectionIndices(of: sample)
    for (iPos, iIdx) in indices.enumerated() {
        for jIdx in indices.dropFirst(iPos) {
            var copy = sample
            let originalI = sample[iIdx]
            let originalJ = sample[jIdx]
            copy.swapAt(iIdx, jIdx)
            if copy[iIdx] != originalJ || copy[jIdx] != originalI {
                return "swapAt(idx[\(iPos)], …) on \(snapshot(sample)) "
                    + "left c[i] = \(copy[iIdx]), c[j] = \(copy[jIdx]); "
                    + "expected c[i] = \(originalJ), c[j] = \(originalI)"
            }
        }
    }
    return nil
}

private func swapAtInvolutionCounterexample<C: MutableCollection>(
    for sample: C
) -> String?
where C.Element: Equatable {
    let original = Array(sample)
    let indices = mutableCollectionIndices(of: sample)
    for (iPos, iIdx) in indices.enumerated() {
        for jIdx in indices.dropFirst(iPos) {
            var copy = sample
            copy.swapAt(iIdx, jIdx)
            copy.swapAt(iIdx, jIdx)
            let after = Array(copy)
            if after != original {
                return "swapAt(idx[\(iPos)], …) twice on \(original.prefix(8))… "
                    + "yielded \(after.prefix(8))…, expected identity"
            }
        }
    }
    return nil
}

private func mutableCollectionIndices<C: Collection>(of sample: C) -> [C.Index] {
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
    return indices
}

private func snapshot<C: Collection>(_ sample: C) -> String {
    "\(Array(sample.prefix(8)))…"
}
