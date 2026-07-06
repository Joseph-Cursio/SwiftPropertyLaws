import PropertyBased

/// v3.3.0 — runtime harness for the `ValueSemantic` protocol. Samples a
/// script of mutations, applies it to a *copy* of a probe, and asserts the
/// original is untouched — the book's copy-mutate-compare property
/// (Chapter 9 §9.1.2).
///
/// **One Strict-tier law per call** — `copyMutationDoesNotLeak`.
///
/// ## How a leak is observed
///
/// The harness constructs **two** independent, equal-valued probes via
/// `makeProbe()`: `original` (the instance under observation) and `reference`
/// (a pristine twin). It copies `original` into `copy`, applies the sampled
/// mutation script to `copy` *alone*, then checks `original == reference`.
///
/// Comparing against an independent twin — rather than a value-copied snapshot
/// of `original` — is deliberate: a leaky type shares reference-backed storage
/// across value copies, so a snapshot `let before = original` would share that
/// storage and mutate in lockstep, hiding the leak. Two probes built by
/// separate `makeProbe()` calls hold *separate* storage, so a mutation that
/// bleeds from `copy` into `original` moves `original` away from the pristine
/// `reference` and the law fails. A correct value type (or a correct
/// copy-on-write type whose `isKnownUniquelyReferenced` guard fires on every
/// mutating path) keeps `original == reference` and passes.
///
/// ## Shrinking (Chapter 9 §9.2.3)
///
/// On failure the driver shrinks the mutation script by dropping cases one at
/// a time, landing on the minimal "copy, then apply *these* mutation(s)"
/// reproduction — the book's target for making a value-semantics failure
/// actionable.
@discardableResult
public func checkValueSemanticPropertyLaws<Value: ValueSemantic & Sendable>(
    for type: Value.Type = Value.self,
    length: ClosedRange<Int> = ActionSequenceFactory.defaultLength,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    try await runPropertyLawSuite(options: options) {
        [
            await checkCopyMutationDoesNotLeak(
                for: type,
                length: length,
                options: options
            )
        ]
    }
}

// MARK: - Per-law internals

/// v3.3.0 — the copy-mutate-compare check. Sample a mutation script, apply it
/// to a copy of a probe, and verify the original stays equal to an untouched
/// twin. A failure means a mutation to the copy was observable through the
/// original — shared mutable state leaking through a "value" type.
private func checkCopyMutationDoesNotLeak<Value: ValueSemantic & Sendable>(
    for type: Value.Type,
    length: ClosedRange<Int>,
    options: LawCheckOptions
) async -> CheckResult
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    let scriptGen = ActionSequenceFactory.actionSequence(
        forCaseIterable: Value.Mutation.self,
        length: length
    )
    return await PerLawDriver.run(
        protocolLaw: "ValueSemantic.copyMutationDoesNotLeak",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in scriptGen.run(using: &rng) },
            property: { script in
                let original = Value.makeProbe()
                let reference = Value.makeProbe()
                var copy = original
                for mutation in script {
                    Value.apply(mutation, to: &copy)
                }
                return original == reference
            },
            formatCounterexample: { script, _ in
                formatValueSemanticLeak(of: Value.self, script: script)
            },
            shrink: { script in dropOneAtATime(script) }
        )
    )
}

/// Shrinker for a mutation script — every subsequence with one element
/// removed. Greedy descent (`PerLawDriver.minimize`) walks these down to the
/// minimal still-failing script, the "copy, then this one method" repro.
private func dropOneAtATime<Mutation: Sendable>(_ script: [Mutation]) -> [[Mutation]] {
    guard !script.isEmpty else { return [] }
    return script.indices.map { index in
        var reduced = script
        reduced.remove(at: index)
        return reduced
    }
}

// MARK: - Counterexample formatting

/// v3.3.0 — describe the leaking script. An empty failing script means the two
/// probes weren't equal to begin with — a non-deterministic `makeProbe()`,
/// reported as such rather than as a copy-independence leak.
private func formatValueSemanticLeak<Value: ValueSemantic>(
    of type: Value.Type,
    script: [Value.Mutation]
) -> String {
    guard !script.isEmpty else {
        return "\(Value.self): two independently-built probes are not equal "
            + "before any mutation — `makeProbe()` must return an equal-valued, "
            + "independently-constructed instance on every call."
    }
    let steps = script.map { "\($0)" }.joined(separator: ", ")
    return "\(Value.self) leaks shared mutable state: after copying a probe and "
        + "applying [\(steps)] to the copy alone, the original changed "
        + "(original != an untouched twin). Minimal reproduction: copy, then "
        + "apply the \(script.count) listed mutation(s)."
}
