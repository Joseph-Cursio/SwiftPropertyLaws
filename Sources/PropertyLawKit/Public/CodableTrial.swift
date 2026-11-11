import PropertyBased

/// Whole-trial sample for Codable: captures the original input, the restored
/// value (or the encode/decode error), in a Sendable shape so the backend
/// closure boundary stays clean.
enum CodableTrial<Value: Codable & Equatable & Sendable>: Sendable {
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
        case let .roundTripped(original, restored):
            return formatMismatch(original: original, restored: restored, mode: mode)

        case let .threw(original, error):
            return "x = \(original); encode/decode threw: \(error.message)"
        }
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
