import Foundation
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
    for type: Value.Type = Value.self,
    using generator: Generator<Value, Shrinker>,
    config: CodableLawConfig<Value> = CodableLawConfig(),
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
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
                    case .roundTripped(let original, let restored):
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

/// Whole-trial sample for Codable: captures the original input, the restored
/// value (or the encode/decode error), in a Sendable shape so the backend
/// closure boundary stays clean.
private enum CodableTrial<Value: Codable & Equatable & Sendable>: Sendable {
    case roundTripped(original: Value, restored: Value)
    case threw(original: Value, error: ErrorBox)

    static func run<Shrinker: SendableSequenceType>(
        generator: Generator<Value, Shrinker>,
        rng: inout Xoshiro,
        codec: CodableCodec<Value>
    ) -> CodableTrial<Value> {
        let value = generator.run(using: &rng)
        do {
            let data = try codec.encode(value)
            let restored = try codec.decode(data)
            return .roundTripped(original: value, restored: restored)
        } catch {
            return .threw(original: value, error: ErrorBox(error))
        }
    }

    static func format(trial: CodableTrial<Value>, mode: CodableRoundTripMode<Value>) -> String {
        switch trial {
        case .roundTripped(let original, let restored):
            return formatMismatch(original: original, restored: restored, mode: mode)
        case .threw(let original, let error):
            return "x = \(original); encode/decode threw: \(error.message)"
        }
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

private func formatMismatch<Value>(
    original: Value,
    restored: Value,
    mode: CodableRoundTripMode<Value>
) -> String where Value: Equatable & Sendable {
    switch mode {
    case .strict:
        return "x = \(original), restored = \(restored); !(x == restored) under .strict"
    case .semantic:
        return "x = \(original), restored = \(restored); semantic equivalence returned false"
    case .partial(let fields):
        for keyPath in fields {
            let originalField = String(describing: original[keyPath: keyPath])
            let restoredField = String(describing: restored[keyPath: keyPath])
            if originalField != restoredField {
                return "x = \(original), restored = \(restored); "
                    + "field at \(keyPath) differs: "
                    + "\"\(originalField)\" vs \"\(restoredField)\""
            }
        }
        return "x = \(original), restored = \(restored); .partial mode failure"
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

extension CodableRoundTripMode {
    /// `.semantic` and `.partial` can pass with field-level diffs; `.strict`
    /// can't (any diff is the violation), so near-miss tracking is moot
    /// there.
    fileprivate var tracksFieldLevelNearMisses: Bool {
        switch self {
        case .strict: return false
        case .semantic, .partial: return true
        }
    }
}
