import Foundation
import PropertyBased

/// Violates Codable.roundTripFidelity: `encode` writes both fields but
/// `decode` always sets `secret` to a constant default. Strict mode catches
/// it; `.partial(fields: [\\.id])` does not (id round-trips fine).
struct DroppingFieldRecord: Codable, Equatable, Sendable, CustomStringConvertible {
    let id: Int
    let secret: String

    enum CodingKeys: String, CodingKey {
        case id
        case secret
    }

    init(id: Int, secret: String) {
        self.id = id
        self.secret = secret
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        self.secret = "REDACTED" // <-- silently overrides whatever was encoded
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(secret, forKey: .secret)
    }

    var description: String { "DFR(id:\(id), secret:\"\(secret)\")" }
}

extension Gen where Value == DroppingFieldRecord {
    static func droppingFieldRecord() -> Generator<DroppingFieldRecord, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0...1_000),
            Gen<Character>.letterOrNumber.string(of: 1...4)
        ).map { id, secret in
            DroppingFieldRecord(id: id, secret: secret)
        }
    }
}
