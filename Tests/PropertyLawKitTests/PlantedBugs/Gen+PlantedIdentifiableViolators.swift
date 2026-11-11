import Foundation
import PropertyBased

/// Violates Identifiable.idStability. `id` is computed as a fresh UUID on
/// every read — the canonical "no two reads agree" failure mode for an
/// Identifiable that should have used a stored property.
struct EphemeralID: Identifiable, Sendable, CustomStringConvertible {
    let label: String
    var id: UUID { UUID() }
    var description: String { "Eph(\(label))" }
}

extension Gen where Value == EphemeralID {
    static func ephemeralID() -> Generator<EphemeralID, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 1...4).map { EphemeralID(label: $0) }
    }
}
