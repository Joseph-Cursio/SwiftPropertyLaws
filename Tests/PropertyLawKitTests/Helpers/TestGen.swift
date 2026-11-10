import PropertyBased

/// Convenience: a string generator built from the upstream's letter-or-number
/// generator at moderate length.
enum TestGen {
    static func smallString() -> Generator<String, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 0...8)
    }

    static func smallInt() -> Generator<Int, some SendableSequenceType> {
        Gen<Int>.int(in: -100...100)
    }
}

extension Gen where Value == Coordinate {
    /// Coordinates with small components so collisions are likely (good for
    /// hashable tests).
    static func coordinate() -> Generator<Coordinate, some SendableSequenceType> {
        zip(Gen<Int>.int(in: -50...50), Gen<Int>.int(in: -50...50))
            .map { Coordinate(easting: $0, northing: $1) }
    }
}
