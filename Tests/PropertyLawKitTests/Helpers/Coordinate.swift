import Foundation

/// A small value-type struct used as the third stdlib-adjacent target for
/// green-path tests. Hand-written `Equatable`/`Hashable` so the law checker
/// is exercising real implementations rather than synthesized ones.
struct Coordinate: Equatable, Hashable, Sendable, CustomStringConvertible {
    let easting: Int
    let northing: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.easting == rhs.easting && lhs.northing == rhs.northing
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(easting)
        hasher.combine(northing)
    }

    var description: String { "(\(easting), \(northing))" }
}
