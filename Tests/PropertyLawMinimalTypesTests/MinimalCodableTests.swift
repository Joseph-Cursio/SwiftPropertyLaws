import Foundation
import PropertyBased
import PropertyLawKit
import PropertyLawMinimalTypes
import Testing

@Suite("Minimal Codable")
struct MinimalCodableTests {

    private struct Point: Codable, Equatable, Sendable {
        var x: Int
        var y: Int
    }

    private struct Widths: Codable, Equatable, Sendable {
        var small: Int32
        var wide: Int64
        var unsigned: UInt
    }

    // MARK: - The distinction JSON erases

    /// The reason this codec exists. JSON has one number type, so these three encode to the same
    /// token; the typed tree keeps them apart.
    @Test("Width and signedness survive the encoding")
    func widthsAreDistinguished() throws {
        #expect(try MinimalEncoder.encode(5 as Int) == .int(5))
        #expect(try MinimalEncoder.encode(5 as Int64) == .int64(5))
        #expect(try MinimalEncoder.encode(5 as UInt) == .uint(5))
        #expect(try MinimalEncoder.encode(5 as Int) != MinimalEncoder.encode(5 as Int64))
    }

    /// JSON will hand an `Int64` back as an `Int` without complaint. The minimal decoder will
    /// not, and says which case it found.
    @Test("Decoding a mismatched width fails rather than converting")
    func mismatchedWidthIsRefused() throws {
        let tree = try MinimalEncoder.encode(5 as Int64)
        #expect(throws: (any Error).self) {
            try MinimalDecoder.decode(Int.self, from: tree)
        }
        #expect(try MinimalDecoder.decode(Int64.self, from: tree) == 5)
    }

    /// All fourteen leaf types, each with the case it must encode to. A type the codec does not
    /// treat as a leaf never encodes at all: it asks for a single-value container, which hands
    /// it straight back, so the call recurses until the stack runs out.
    @Test("Every leaf type encodes to its own case and decodes back from it")
    func everyLeafTypeRoundTripsThroughItsOwnCase() throws {
        try expectLeaf(true, encodesTo: .bool(true))
        try expectLeaf(-5 as Int, encodesTo: .int(-5))
        try expectLeaf(-5 as Int8, encodesTo: .int8(-5))
        try expectLeaf(-5 as Int16, encodesTo: .int16(-5))
        try expectLeaf(-5 as Int32, encodesTo: .int32(-5))
        try expectLeaf(-5 as Int64, encodesTo: .int64(-5))
        try expectLeaf(5 as UInt, encodesTo: .uint(5))
        try expectLeaf(5 as UInt8, encodesTo: .uint8(5))
        try expectLeaf(5 as UInt16, encodesTo: .uint16(5))
        try expectLeaf(5 as UInt32, encodesTo: .uint32(5))
        try expectLeaf(5 as UInt64, encodesTo: .uint64(5))
        try expectLeaf(1.5 as Float, encodesTo: .float(1.5))
        try expectLeaf(1.5 as Double, encodesTo: .double(1.5))
        try expectLeaf("five", encodesTo: .string("five"))
    }

    private func expectLeaf<T: Codable & Equatable>(
        _ value: T,
        encodesTo expected: MinimalCodableValue,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        #expect(try MinimalEncoder.encode(value) == expected, sourceLocation: sourceLocation)
        #expect(try MinimalDecoder.decode(T.self, from: expected) == value, sourceLocation: sourceLocation)
    }

    @Test("A struct encodes to a dictionary of its keys")
    func structEncodesToDictionary() throws {
        let tree = try MinimalEncoder.encode(Point(x: 1, y: 2))
        #expect(tree == .dictionary(["x": .int(1), "y": .int(2)]))
    }

    @Test("Round trip through the minimal codec preserves the value")
    func roundTripPreservesValue() throws {
        let codec = CodableCodec<Widths>.minimal
        let original = Widths(small: -3, wide: 1 << 40, unsigned: 7)
        let restored = try codec.decode(codec.encode(original))
        #expect(restored == original)
    }

    @Test("Arrays and nesting round trip")
    func nestedRoundTrip() throws {
        let codec = CodableCodec<[Point]>.minimal
        let original = [Point(x: 1, y: 2), Point(x: -4, y: 0)]
        #expect(try codec.decode(codec.encode(original)) == original)
    }

    @Test("Optionals encode as null and come back")
    func optionalsRoundTrip() throws {
        struct Maybe: Codable, Equatable, Sendable { var value: Int? }
        let codec = CodableCodec<Maybe>.minimal
        #expect(try codec.decode(codec.encode(Maybe(value: nil))) == Maybe(value: nil))
        #expect(try codec.decode(codec.encode(Maybe(value: 9))) == Maybe(value: 9))
    }

    // MARK: - Plugged into the existing law suite

    /// The payoff: the kit's own Codable law, run through an encoder that does not convert
    /// between number types. A type that only round-trips because JSON is permissive fails here.
    @Test("Codable laws hold under the minimal codec")
    func codableLawsHoldUnderMinimalCodec() async throws {
        let generator = zip(
            Gen<Int>.int(in: -1000 ... 1000),
            Gen<Int>.int(in: -1000 ... 1000)
        ).map { Point(x: $0, y: $1) }
        let results = try await checkCodablePropertyLaws(
            for: Point.self,
            using: generator,
            config: CodableLawConfig(codec: .minimal),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
