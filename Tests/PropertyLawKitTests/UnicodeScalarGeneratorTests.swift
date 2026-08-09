import PropertyBased
import Testing
@testable import PropertyLawKit

/// `Unicode.Scalar` was an enum-payload blocker on the swift.org corpus and the
/// only *stdlib* one in the tail — `Character` was already in the kit's
/// known-value table and its scalar sibling was not.
///
/// The generator is banded rather than uniform, and both halves of that choice
/// are testable: a uniform draw over `0 ... 0x10FFFF` is ~97% unassigned
/// planes-3-to-13 code points, so the boundaries that actually break text code
/// would each be reached at negligible rates.
struct UnicodeScalarGeneratorTests {

    private func sample(count: Int, seed: UInt64 = 1) -> [Unicode.Scalar] {
        var rng = Xoshiro(seed: (seed, seed &+ 1, seed &+ 2, seed &+ 3))
        let generator = Gen<Unicode.Scalar>.unicodeScalar()
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    /// The load-bearing one. `Unicode.Scalar(_:)` returns `nil` for the
    /// surrogate range, so a band that included it would force a `compactMap`
    /// that silently drops samples and skews the very distribution the bands
    /// exist to control. Every band excludes it by construction.
    @Test("no sample lands in the surrogate range")
    func neverProducesSurrogates() {
        for scalar in sample(count: 5000) {
            #expect(scalar.value < 0xD800 || scalar.value > 0xDFFF,
                    "surrogate code point \(scalar.value) is not a valid scalar")
        }
    }

    /// Each band has to be reachable, or the weights are decoration.
    @Test("every band is reached")
    func everyBandIsReached() {
        let values = sample(count: 5000).map(\.value)
        #expect(values.contains { (0x20 ... 0x7E).contains($0) }, "ASCII band unreached")
        #expect(values.contains { (0x00A0 ... 0x017F).contains($0) }, "Latin band unreached")
        #expect(values.contains { (0x0180 ... 0xD7FF).contains($0) }, "low-BMP band unreached")
        #expect(values.contains { (0xE000 ... 0xFFFD).contains($0) }, "high-BMP band unreached")
        #expect(values.contains { $0 >= 0x10000 }, "astral band unreached")
    }

    /// ASCII carries the heaviest weight because it is what most code is
    /// written against — but it must not swamp the rest, or the boundaries are
    /// out of reach again.
    @Test("ASCII is favoured without dominating")
    func asciiIsWeightedNotDominant() {
        let values = sample(count: 5000).map(\.value)
        let ascii = Double(values.filter { (0x20 ... 0x7E).contains($0) }.count)
        let ratio = ascii / Double(values.count)
        #expect(ratio > 0.25, "ASCII ratio \(ratio) — the weighting is not taking effect")
        #expect(ratio < 0.65, "ASCII ratio \(ratio) — the other bands are being crowded out")
    }

    /// Astral scalars are the ones that need a surrogate pair in UTF-16 — the
    /// classic place a "one scalar is one code unit" assumption breaks.
    @Test("astral scalars appear often enough to matter")
    func astralScalarsAppear() {
        let astral = sample(count: 1000).filter { $0.value >= 0x10000 }
        #expect(astral.count > 20, "only \(astral.count)/1000 astral scalars")
    }

    @Test("the same seed replays")
    func seededReplay() {
        #expect(sample(count: 100).map(\.value) == sample(count: 100).map(\.value))
    }

    @Test("different seeds differ")
    func differentSeedsDiffer() {
        #expect(sample(count: 100, seed: 1).map(\.value)
            != sample(count: 100, seed: 99).map(\.value))
    }

    /// Every produced value round-trips through `String`, which is the property
    /// a caller actually relies on when a scalar is an enum payload.
    @Test("every sample round-trips through String")
    func roundTripsThroughString() {
        for scalar in sample(count: 1000) {
            let string = String(scalar)
            #expect(string.unicodeScalars.count == 1)
            #expect(string.unicodeScalars.first == scalar)
        }
    }
}
