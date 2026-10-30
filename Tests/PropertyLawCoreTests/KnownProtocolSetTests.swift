import Testing
@testable import PropertyLawCore

/// `KnownProtocol.set(from:)` reads an inheritance clause for both the macro
/// and the discovery plugin, and adds two conformances the clause does not
/// spell: `Codable` from `Encodable` plus `Decodable`, and `Comparable` from
/// `Strideable`.
///
/// Every fixture in the macro's tests that wrote `Encodable` also wrote
/// `Decodable`, so a pairing that fired on either half passed them. That half
/// is the dangerous one: a type that is only `Encodable` would get a Codable
/// suite it cannot compile.
struct KnownProtocolSetTests {

    @Test("Encodable and Decodable together are Codable")
    func bothHalvesAreCodable() {
        #expect(KnownProtocol.set(from: ["Encodable", "Decodable"]).contains(.codable))
    }

    @Test(
        "one half of Codable, beside another protocol, is not Codable",
        arguments: [["Encodable"], ["Decodable"], ["Encodable", "Equatable"], ["Decodable", "Equatable"]]
    )
    func oneHalfIsNotCodable(names: [String]) {
        #expect(!KnownProtocol.set(from: names).contains(.codable))
    }

    @Test("Strideable implies Comparable, and nothing else does")
    func strideableImpliesComparable() {
        #expect(KnownProtocol.set(from: ["Strideable"]) == [.strideable, .comparable])
        #expect(KnownProtocol.set(from: ["Hashable"]) == [.hashable])
    }
}
