import PropertyBased
import Testing
@testable import PropertyLawKit

/// **Seeded reproducibility for the NaN-injecting generators.**
///
/// `doubleWithNaN()` / `floatWithNaN()` used `Double.random(in:)` for the finite
/// path — the *system* RNG, which no seed can reach. The NaN positions replayed
/// (the tag was seeded) and the finite values did not, so a FloatingPoint law
/// that failed on an ordinary value could not be reproduced from the seed it
/// failed under. That is exactly the case where the exact input matters: an
/// edge-case failure is usually legible from the value, a finite-value failure
/// is not.
///
/// Nothing caught it. The generators were used by `FloatingPointLawsTests` and
/// `SameResultTests` on every run, and both pass either way — a law that holds
/// does not care whether its inputs are reproducible. The defect is only visible
/// if you ask the question directly, which is what these tests do.
///
/// Found by pointing SwiftProjectLint's `Non-Injected Nondeterminism` rule at
/// this repo
/// (`SwiftInferProperties/docs/measurements/roadtest-self-dogfood.md` §14).
///
/// **`PropertyLawComplex.edgeCaseBiased()` is deliberately exempt.** It keeps an
/// unseeded finite path and documents it, with `determinismOnSeededTagDecisions`
/// pinning determinism on the seeded sub-stream only — there the curated edge
/// cases are the payload and the finite filler is noise. Here the finite value
/// *is* the sample the always-on laws run against.
@Suite("NaN-injecting generators are reproducible from a seed")
struct NaNGeneratorSeedingTests {

    private static func seededRNG() -> any SeededRandomNumberGenerator {
        Xoshiro(seed: (0xDEAD_BEEF, 0xCAFE_F00D, 0x1234_5678, 0x9ABC_DEF0))
    }

    private static func drawDoubles(count: Int) -> [Double] {
        var rng = seededRNG()
        let generator = Gen<Double>.doubleWithNaN()
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    private static func drawFloats(count: Int) -> [Float] {
        var rng = seededRNG()
        let generator = Gen<Float>.floatWithNaN()
        return (0 ..< count).map { _ in generator.run(using: &rng) }
    }

    /// Bit-for-bit equality, NaN-aware. The previous implementation passed the
    /// NaN half of this and failed the finite half.
    private static func identical(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        lhs.count == rhs.count
            && zip(lhs, rhs).allSatisfy { ($0.isNaN && $1.isNaN) || $0.bitPattern == $1.bitPattern }
    }

    @Test("doubleWithNaN replays exactly from the same seed")
    func doubleReplaysFromSeed() {
        let first = Self.drawDoubles(count: 200)
        let second = Self.drawDoubles(count: 200)
        #expect(
            Self.identical(first, second),
            """
            The same seed produced different values. A law failing on one of them \
            cannot be replayed — check that the finite path uses \
            `Gen<Double>.double(in:)` and not `Double.random(in:)`.
            """
        )
    }

    @Test("floatWithNaN replays exactly from the same seed")
    func floatReplaysFromSeed() {
        let first = Self.drawFloats(count: 200)
        let second = Self.drawFloats(count: 200)
        #expect(first.count == second.count)
        #expect(
            zip(first, second).allSatisfy { ($0.isNaN && $1.isNaN) || $0.bitPattern == $1.bitPattern }
        )
    }

    /// **The half that already worked, kept as a control.** If a future change
    /// broke seeding entirely, `doubleReplaysFromSeed` would fail and this would
    /// too — and only having both tells you whether the tag or the value moved.
    @Test("the NaN positions are seeded, not incidental")
    func nanPositionsAreSeeded() {
        let first = Self.drawDoubles(count: 200)
        let second = Self.drawDoubles(count: 200)
        #expect(first.map(\.isNaN) == second.map(\.isNaN))
    }

    /// **The finite values must actually vary.** A "fix" that returned a
    /// constant would satisfy every replay assertion above and destroy the
    /// generator. This is the degenerate-input guard — the same failure mode
    /// that made a narrowed-entropy sweep vacuous in the consuming repo.
    @Test("the finite values are varied, not constant")
    func finiteValuesVary() {
        let finite = Self.drawDoubles(count: 200).filter { !$0.isNaN }
        #expect(finite.count > 150, "expected ~95% finite, got \(finite.count)/200")
        #expect(Set(finite).count > 100, "finite values collapsed to \(Set(finite).count) distinct")
    }

    /// The documented ~1-in-20 NaN rate survives the rewrite. Loose bounds —
    /// this pins the design intent, not a sampling artefact.
    @Test("the NaN injection rate stays near 1 in 20")
    func nanRateIsPreserved() {
        let samples = Self.drawDoubles(count: 2_000)
        let nanCount = samples.filter(\.isNaN).count
        #expect((50...150).contains(nanCount), "expected ~100 NaN in 2000, got \(nanCount)")
    }

    /// Different seeds must produce different streams — otherwise "reproducible"
    /// would be satisfied by ignoring the seed altogether.
    @Test("different seeds produce different streams")
    func differentSeedsDiffer() {
        var rngA: any SeededRandomNumberGenerator = Xoshiro(seed: (1, 2, 3, 4))
        var rngB: any SeededRandomNumberGenerator = Xoshiro(seed: (9, 8, 7, 6))
        let generator = Gen<Double>.doubleWithNaN()
        let streamA = (0 ..< 50).map { _ in generator.run(using: &rngA) }
        let streamB = (0 ..< 50).map { _ in generator.run(using: &rngB) }
        #expect(!Self.identical(streamA, streamB))
    }
}
