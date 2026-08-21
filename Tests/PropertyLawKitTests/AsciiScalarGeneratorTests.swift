import PropertyBased
import Testing
@testable import PropertyLawKit

/// The ASCII-restricted sibling of `unicodeScalar()`, for parameters whose **label** declares
/// a domain their type does not — `init(ascii: Unicode.Scalar)`.
///
/// Measured 2026-08-21 on `swift-system` @ `6a63f08` (SwiftInferProperties,
/// `docs/measurements/criterion-a-swift-system.md` §2): derivation paired `unicodeScalar()`
/// with `SystemChar(ascii:)`, and **9 of the 19 laws that reached the build stage compiled,
/// linked, ran and died** on `Fatal error: Code point value does not fit into ASCII`.
struct AsciiScalarGeneratorTests {

    private func sample(count: Int, seed: UInt64 = 1) -> [Unicode.Scalar] {
        var rng = Xoshiro(seed: (seed, seed &+ 1, seed &+ 2, seed &+ 3))
        let generator = Gen<Unicode.Scalar>.asciiScalar()
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    /// **The load-bearing arm — this is the whole reason the generator exists.** It is stated
    /// as `isASCII` rather than as a numeric bound on purpose: `isASCII` is the property the
    /// stdlib itself vends and the one `init(ascii:)` preconditions on, so this asserts the
    /// contract rather than a restatement of the band table.
    @Test("no sample is outside ASCII")
    func neverProducesNonASCII() {
        for scalar in sample(count: 5000) {
            #expect(scalar.isASCII, "scalar \(scalar.value) is not ASCII")
        }
    }

    /// Each band has to be reachable, or the weights are decoration — and the control bands
    /// are the ones a "realistic" alphabet would have omitted, which is the point of including
    /// them. See `fixtures/branch-reaching-generator/` in SwiftInferProperties: a narrow
    /// alphabet *with controls* was the lever that killed a mutant where a wider alphanumeric
    /// one killed nothing.
    @Test("every band is reached")
    func everyBandIsReached() {
        let values = sample(count: 5000).map(\.value)
        #expect(values.contains { (0x20 ... 0x7E).contains($0) }, "printable band unreached")
        #expect(values.contains { $0 == 0x09 }, "tab unreached")
        #expect(values.contains { $0 == 0x0A }, "newline unreached")
        #expect(values.contains { $0 == 0x0D }, "carriage return unreached")
        #expect(values.contains { $0 == 0x00 }, "NUL unreached")
        #expect(values.contains { $0 == 0x7F }, "DEL unreached")
    }

    /// Printable must dominate without swamping. A suite that is mostly control characters
    /// tests a different program than the one under test; one that never reaches a control
    /// character is the generator this replaces, wearing a narrower range.
    @Test("printable dominates but does not swamp")
    func theWeightsAreHonoured() {
        let values = sample(count: 5000).map(\.value)
        let printable = values.filter { (0x20 ... 0x7E).contains($0) }.count
        let share = Double(printable) / Double(values.count)
        #expect(share > 0.5, "printable share \(share) is too low to be the common case")
        #expect(share < 0.8, "printable share \(share) leaves controls at negligible rates")
    }

    /// Seeded end to end: the same seed must give the same sequence, and different seeds
    /// must not. Without this a "generator" that ignored the RNG would pass every arm above.
    @Test("the draw is fully seeded")
    func theDrawIsSeeded() {
        #expect(sample(count: 200, seed: 7).map(\.value) == sample(count: 200, seed: 7).map(\.value))
        #expect(sample(count: 200, seed: 7).map(\.value) != sample(count: 200, seed: 8).map(\.value))
    }
}
