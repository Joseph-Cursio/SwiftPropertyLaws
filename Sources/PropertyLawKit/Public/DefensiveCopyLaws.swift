import PropertyBased

/// v3.7.0 — runtime harness for the `DefensiveCopy` protocol (pbt-book Ch. 9
/// §9.3). Two Strict-tier laws:
///
///   - `copyIsDistinctInstance` — `x.copyUnderTest() !== x`. A defensive copy
///     must be a *new object*; a `copy()` that returns `self` is the classic bug.
///   - `copyIsIndependent` — mutating `x.copyUnderTest()` must not affect `x`.
///     The `ValueSemantic` copy-mutate-compare law with the copy operation being
///     `copyUnderTest()`; catches a shallow copy sharing a mutable reference.
///
/// Leak observation mirrors `ValueSemantic`: two independent, equal-valued
/// probes (`original`, a pristine `reference`), and a comparison against the
/// twin — never a snapshot of `original`, which would share the leaked storage.
@discardableResult
public func checkDefensiveCopyPropertyLaws<Value: DefensiveCopy & Sendable>(
    for type: Value.Type = Value.self,
    length: ClosedRange<Int> = ActionSequenceFactory.defaultLength,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    try await runPropertyLawSuite(options: options) {
        [
            await checkCopyIsDistinctInstance(for: type, length: length, options: options),
            await checkCopyIsIndependent(for: type, length: length, options: options)
        ]
    }
}

// MARK: - Per-law internals

/// `x.copyUnderTest() !== x` — after driving `x` to an arbitrary reachable state,
/// its copy must be a distinct object. `false` ⇒ the copy method returned `self`.
private func checkCopyIsDistinctInstance<Value: DefensiveCopy & Sendable>(
    for type: Value.Type,
    length: ClosedRange<Int>,
    options: LawCheckOptions
) async -> CheckResult
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    let scriptGen = ActionSequenceFactory.actionSequence(forCaseIterable: Value.Mutation.self, length: length)
    return await PerLawDriver.run(
        protocolLaw: "DefensiveCopy.copyIsDistinctInstance",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in scriptGen.run(using: &rng) },
            property: { script in
                let subject = Value.makeProbe()
                for mutation in script {
                    Value.apply(mutation, to: subject)
                }
                return subject.copyUnderTest() !== subject
            },
            formatCounterexample: { _, _ in
                "\(Value.self).copyUnderTest() returned the SAME instance (=== the "
                    + "source), not a distinct object — a defensive copy must return "
                    + "a new object (the `return self` bug)."
            }
        )
    )
}

/// Mutating `x.copyUnderTest()` must not affect `x`. The `ValueSemantic`
/// independent-twin check with copy via `copyUnderTest()`; `false` ⇒ the copy
/// shares mutable reference state with the source (a shallow copy).
private func checkCopyIsIndependent<Value: DefensiveCopy & Sendable>(
    for type: Value.Type,
    length: ClosedRange<Int>,
    options: LawCheckOptions
) async -> CheckResult
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    let scriptGen = ActionSequenceFactory.actionSequence(forCaseIterable: Value.Mutation.self, length: length)
    return await PerLawDriver.run(
        protocolLaw: "DefensiveCopy.copyIsIndependent",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in scriptGen.run(using: &rng) },
            property: { script in
                let original = Value.makeProbe()
                let reference = Value.makeProbe()
                let copy = original.copyUnderTest()
                for mutation in script {
                    Value.apply(mutation, to: copy)
                }
                return original == reference
            },
            formatCounterexample: { script, _ in
                let steps = script.map { "\($0)" }.joined(separator: ", ")
                return "\(Value.self) makes a shallow copy: after copying and applying "
                    + "[\(steps)] to the copy alone, the source changed (source != an "
                    + "untouched twin) — copyUnderTest() shares mutable reference state "
                    + "with the source. Minimal reproduction: copy, then apply the "
                    + "\(script.count) listed mutation(s)."
            },
            shrink: { script in defensiveCopyDropOne(script) }
        )
    )
}

/// Every subsequence with one element removed — greedy descent lands on the
/// minimal "copy, then this one method" reproduction.
private func defensiveCopyDropOne<Mutation: Sendable>(_ script: [Mutation]) -> [[Mutation]] {
    guard !script.isEmpty else { return [] }
    return script.indices.map { index in
        var reduced = script
        reduced.remove(at: index)
        return reduced
    }
}
