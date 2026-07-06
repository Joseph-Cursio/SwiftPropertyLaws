import PropertyBased

/// v3.8.0 — runtime harness for the `StableIdentity` protocol (pbt-book Ch. 9
/// §9.3.3). Two Strict-tier laws that drive the mutation surface and assert the
/// object's identity is undisturbed:
///
///   - `hashStableUnderMutation` — `hashValue` invariant across mutation.
///   - `equalityStableUnderMutation` — equality to an independent twin invariant
///     across mutation.
///
/// A confirmed failure means the type's `==` / `hash` reads mutable state, so an
/// instance is unsafe to use as a `Set` / `Dictionary` key. (`hashValue` is
/// randomly seeded per process but constant *within* a run, so the before/after
/// comparison inside one property trial is well-defined.)
@discardableResult
public func checkStableIdentityPropertyLaws<Value: StableIdentity & Sendable>(
    for type: Value.Type = Value.self,
    length: ClosedRange<Int> = ActionSequenceFactory.defaultLength,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult]
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    try await runPropertyLawSuite(options: options) {
        [
            await checkHashStableUnderMutation(for: type, length: length, options: options),
            await checkEqualityStableUnderMutation(for: type, length: length, options: options)
        ]
    }
}

// MARK: - Per-law internals

/// `hashValue` must not change as the object is mutated. Checked after each
/// step so the first identity-disturbing mutation is the counterexample.
private func checkHashStableUnderMutation<Value: StableIdentity & Sendable>(
    for type: Value.Type,
    length: ClosedRange<Int>,
    options: LawCheckOptions
) async -> CheckResult
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    let scriptGen = ActionSequenceFactory.actionSequence(forCaseIterable: Value.Mutation.self, length: length)
    return await PerLawDriver.run(
        protocolLaw: "StableIdentity.hashStableUnderMutation",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in scriptGen.run(using: &rng) },
            property: { script in
                let subject = Value.makeProbe()
                let originalHash = subject.hashValue
                for mutation in script {
                    Value.apply(mutation, to: subject)
                    if subject.hashValue != originalHash { return false }
                }
                return true
            },
            formatCounterexample: { script, _ in
                identityCounterexample(of: Value.self, script: script, reads: "hashValue")
            },
            shrink: { script in stableIdentityDropOne(script) }
        )
    )
}

/// Whether the object equals an independent, equal-valued twin must not change
/// as the object is mutated.
private func checkEqualityStableUnderMutation<Value: StableIdentity & Sendable>(
    for type: Value.Type,
    length: ClosedRange<Int>,
    options: LawCheckOptions
) async -> CheckResult
where Value.Mutation.AllCases: Sendable & RandomAccessCollection {
    let scriptGen = ActionSequenceFactory.actionSequence(forCaseIterable: Value.Mutation.self, length: length)
    return await PerLawDriver.run(
        protocolLaw: "StableIdentity.equalityStableUnderMutation",
        tier: .strict,
        options: options,
        check: LawCheck(
            sample: { rng in scriptGen.run(using: &rng) },
            property: { script in
                let subject = Value.makeProbe()
                let reference = Value.makeProbe()
                let wereEqual = subject == reference
                for mutation in script {
                    Value.apply(mutation, to: subject)
                    if (subject == reference) != wereEqual { return false }
                }
                return true
            },
            formatCounterexample: { script, _ in
                identityCounterexample(of: Value.self, script: script, reads: "==")
            },
            shrink: { script in stableIdentityDropOne(script) }
        )
    )
}

/// Every subsequence with one element removed — greedy descent lands on the
/// minimal "create, then this one mutation" reproduction.
private func stableIdentityDropOne<Mutation: Sendable>(_ script: [Mutation]) -> [[Mutation]] {
    guard !script.isEmpty else { return [] }
    return script.indices.map { index in
        var reduced = script
        reduced.remove(at: index)
        return reduced
    }
}

private func identityCounterexample<Value: StableIdentity>(
    of type: Value.Type,
    script: [Value.Mutation],
    reads member: String
) -> String {
    let steps = script.map { "\($0)" }.joined(separator: ", ")
    return "\(Value.self).\(member) changed after mutation [\(steps)] — its identity "
        + "reads mutable state, so an instance is unsafe to use as a Set / Dictionary "
        + "key (mutating one already in the collection corrupts it). Minimal "
        + "reproduction: create, then apply the \(script.count) listed mutation(s)."
}
