import ComplexModule
import PropertyBased
import Testing

@testable import PropertyLawComplex

/// Verifies the kit-side contract for `Gen<Complex<Double>>.edgeCaseBiased()`
/// per the proposal at SwiftInferProperties' `docs/ideas/Edge-Case-Biased
/// Generators Kit Proposal.md`.
///
/// The three tests cover the only behaviors the API promises:
///
/// 1. **Distribution.** The 90/10 bias holds within a generous tolerance.
/// 2. **Coverage.** Every entry in `complexEdgeCases` is hit at least once
///    over a single 10 000-trial budget.
/// 3. **Determinism.** Same seed produces identical edge-case sub-streams
///    (the finite path uses `Double.random` non-seeded, so we only assert
///    determinism on the seeded tag decision via the edge-case projection).
struct EdgeCaseBiasedGeneratorsTests {

    private static let trialCount = 10_000

    /// Walk a Xoshiro for `trialCount` trials and collect every sample.
    /// The seed is built from a single `UInt64` so the call sites don't
    /// declare the 4-tuple type that would trip `large_tuple` linting.
    private static func sample(seedTag: UInt64) -> [Complex<Double>] {
        var rng: any SeededRandomNumberGenerator =
            Xoshiro(seed: (seedTag, seedTag &+ 1, seedTag &+ 2, seedTag &+ 3))
        let generator = Gen<Complex<Double>>.edgeCaseBiased()
        var out: [Complex<Double>] = []
        out.reserveCapacity(trialCount)
        for _ in 0 ..< trialCount {
            out.append(generator.run(using: &rng))
        }
        return out
    }

    /// Detect whether a sampled value matches a curated edge case by
    /// componentwise pattern — not by `==`, because IEEE-754 NaN is
    /// `!=` itself. The fingerprint uses the `(isNaN, isInfinite,
    /// sign, magnitude-class)` tuple per component.
    private static func matchesAnyEdgeCase(_ value: Complex<Double>) -> Bool {
        for edgeCase in Gen<Complex<Double>>.complexEdgeCases
        where componentsMatch(value, edgeCase) {
            return true
        }
        return false
    }

    /// Bitwise component match. `Double(bitPattern:)` round-trips NaN
    /// payloads, ±0.0, and ±∞ unambiguously, which the proposal's curated
    /// list cares about (signed zero vs. positive zero are distinct
    /// entries, as are the four ±∞ rotations).
    private static func componentsMatch(_ lhs: Complex<Double>, _ rhs: Complex<Double>) -> Bool {
        let realLhs = lhs.real
        let imagLhs = lhs.imaginary
        let realRhs = rhs.real
        let imagRhs = rhs.imaginary
        let realMatches = bitwiseEqual(realLhs, realRhs)
        let imagMatches = bitwiseEqual(imagLhs, imagRhs)
        return realMatches && imagMatches
    }

    private static func bitwiseEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        if lhs.isNaN, rhs.isNaN { return true }
        return lhs.bitPattern == rhs.bitPattern
    }

    @Test
    func distributionMatches90PercentFinite10PercentEdge() throws {
        let samples = Self.sample(seedTag: 1)
        let edgeHits = samples.filter(Self.matchesAnyEdgeCase).count
        let edgeFraction = Double(edgeHits) / Double(Self.trialCount)
        // Expected 0.10 ± ~0.01 at N=10 000 (binomial std-dev sqrt(0.09/N)
        // ≈ 0.003; 3σ band is ±0.009). Widen to ±0.02 for headroom.
        let inBand = edgeFraction >= 0.08 && edgeFraction <= 0.12
        #expect(inBand, "edge fraction \(edgeFraction), edge hits \(edgeHits) of \(Self.trialCount)")
    }

    @Test
    func coverageHitsEveryCuratedEdgeCase() throws {
        let samples = Self.sample(seedTag: 100)
        let edgeCases = Gen<Complex<Double>>.complexEdgeCases
        for (index, edgeCase) in edgeCases.enumerated() {
            let hit = samples.contains { Self.componentsMatch($0, edgeCase) }
            #expect(hit, "edge case index \(index) (\(edgeCase)) never produced in \(Self.trialCount) trials")
        }
    }

    @Test
    func determinismOnSeededTagDecisions() throws {
        let runA = Self.sample(seedTag: 42)
        let runB = Self.sample(seedTag: 42)
        // Project both streams to "is this trial an edge case, and if so,
        // which one?" The seeded part of the generator decides the tag;
        // the finite-path `Double.random` is non-seeded, so we only
        // compare the edge-case projection.
        let projectionA = runA.map { sample -> Int? in
            Gen<Complex<Double>>.complexEdgeCases.firstIndex {
                Self.componentsMatch(sample, $0)
            }
        }
        let projectionB = runB.map { sample -> Int? in
            Gen<Complex<Double>>.complexEdgeCases.firstIndex {
                Self.componentsMatch(sample, $0)
            }
        }
        #expect(projectionA == projectionB, "same Xoshiro seed produced divergent edge-case sub-streams")
    }
}
