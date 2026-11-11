import PropertyBased

/// Violates RawRepresentable.roundTrip. `init?(rawValue:)` stores the input
/// faithfully, but `rawValue` accessor reports `stored + 1` — so
/// `T(rawValue: x.rawValue) == T(rawValue: stored + 1)` has stored
/// `stored + 1`, which is not equal to `x` (whose stored is `stored`).
struct LossyRawValue: RawRepresentable, Equatable, Sendable, CustomStringConvertible {
    let stored: Int

    init?(rawValue: Int) { self.stored = rawValue }

    var rawValue: Int { stored + 1 }
    var description: String { "LRV(\(stored))" }
}

extension Gen where Value == LossyRawValue {
    static func lossyRawValue() -> Generator<LossyRawValue, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).compactMap { LossyRawValue(rawValue: $0) }
    }
}
