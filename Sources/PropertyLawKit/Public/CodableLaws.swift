import PropertyBased

/// Run `Codable` protocol laws over `Value` (PRD §4.3, §4.7).
///
/// M2 implements **round-trip fidelity** (Conventional tier) under the three
/// PRD-specified modes (`.strict` / `.semantic(equivalent:)` /
/// `.partial(fields:)`). Encoder independence (Conventional) is deferred to a
/// follow-up — the multi-codec orchestration is straightforward but warrants
/// its own design pass for shared-seed semantics across encoders.
///
/// `Value` must be `Equatable` for `.strict` mode; `.semantic` and `.partial`
/// use the caller's predicate / per-field comparison and don't read `==`. Most
/// Codable types in real Swift code are also Equatable, so requiring it keeps
/// the signature simple.
///
/// **Near-miss tracking (M5).** Under `.semantic` and `.partial` modes the
/// law can pass while individual fields disagree (the caller asked for
/// equivalence rather than equality). When that happens, the kit walks the
/// original/restored pair via `Mirror` and records each diverging field on
/// `CheckResult.nearMisses`. Under `.strict`, a field-level diff IS the
/// violation, so no near-miss tracking applies (the field is already in the
/// counterexample).
@discardableResult
public func checkCodablePropertyLaws<
    Value: Codable & Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    config: CodableLawConfig<Value> = CodableLawConfig(),
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    // swiftlint:disable:next closure_body_length - the closure is the suite's law list
    try await runPropertyLawSuite(options: options) {
        let lawName = "Codable.roundTripFidelity[\(config.codec.identifier)]"
        let codec = config.codec
        let mode = config.mode
        let collector: NearMissCollector? = mode.tracksFieldLevelNearMisses
            ? NearMissCollector()
            : nil
        let result = await PerLawDriver.run(
            protocolLaw: lawName,
            tier: .conventional,
            options: options,
            check: LawCheck(
                sample: { rng in
                    CodableTrial<Value>.run(generator: generator, rng: &rng, codec: codec)
                },
                property: { trial in
                    switch trial {
                    case let .roundTripped(original, restored):
                        let passed = comparesEqual(original, restored, mode: mode)
                        if passed, let collector {
                            recordFieldDiffs(
                                original: original,
                                restored: restored,
                                into: collector
                            )
                        }
                        return passed

                    case .threw:
                        return false
                    }
                },
                formatCounterexample: { trial, _ in
                    CodableTrial<Value>.format(trial: trial, mode: mode)
                }
            ),
            observation: PerLawDriver.Observation(nearMissCollector: collector)
        )
        return [result]
    }
}

private func comparesEqual<Value>(
    _ original: Value,
    _ restored: Value,
    mode: CodableRoundTripMode<Value>
) -> Bool where Value: Equatable & Sendable {
    switch mode {
    case .strict:
        return original == restored

    case .semantic(let equivalent):
        return equivalent(original, restored)

    case .partial(let fields):
        for keyPath in fields {
            let originalField = String(describing: original[keyPath: keyPath])
            let restoredField = String(describing: restored[keyPath: keyPath])
            if originalField != restoredField { return false }
        }
        return true
    }
}

/// Mirror-walk both sides and record every field whose `String(describing:)`
/// representations diverge. PRD §4.6: "values where decoded ≠ original on a
/// single field, with the failing field's `KeyPath` reported." Mirror gives
/// us labels rather than KeyPaths — KeyPaths require the caller to enumerate
/// them — but the label-level signal is the actionable one for a reviewer
/// reading test output.
private func recordFieldDiffs<Value>(
    original: Value,
    restored: Value,
    into collector: NearMissCollector
) where Value: Sendable {
    let originalChildren = Array(Mirror(reflecting: original).children)
    let restoredChildren = Array(Mirror(reflecting: restored).children)
    let count = Swift.min(originalChildren.count, restoredChildren.count)
    for index in 0..<count {
        let (label, originalValue) = originalChildren[index]
        let (_, restoredValue) = restoredChildren[index]
        let originalDesc = String(describing: originalValue)
        let restoredDesc = String(describing: restoredValue)
        if originalDesc == restoredDesc { continue }
        let labelText = label ?? "<unlabeled[\(index)]>"
        collector.record(
            "field \(labelText): \"\(originalDesc)\" → \"\(restoredDesc)\""
        )
    }
}
