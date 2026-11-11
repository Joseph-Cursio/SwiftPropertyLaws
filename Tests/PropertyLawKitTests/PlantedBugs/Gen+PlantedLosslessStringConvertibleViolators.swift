import PropertyBased

/// Violates LosslessStringConvertible.roundTrip. `description` includes a
/// suffix that `init(_:)` doesn't strip, so `T(String(describing: x))`
/// stores the suffixed string and produces a value whose own description
/// has *two* suffixes — never equal to `x`.
struct DoublyDescribed: LosslessStringConvertible, Equatable, Sendable {
    let stored: String

    init?(_ description: String) {
        self.stored = description
    }

    var description: String { stored + "_v1" }
}

extension Gen where Value == DoublyDescribed {
    static func doublyDescribed() -> Generator<DoublyDescribed, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 1...6)
            .compactMap { DoublyDescribed($0) }
    }
}
