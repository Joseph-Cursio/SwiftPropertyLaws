import ComplexModule
import PropertyBased
import RealModule

/// Edge-case-biased generators for `Complex<RealType>`.
///
/// Phase 1 (v2.1.0) ships one generator — `Gen<Complex<Double>>.edgeCaseBiased()`
/// — driving SwiftInferProperties' v1.42+ test-execution verify mode. Future
/// minor bumps may extend to `Complex<Float>` and the real-axis `Double` /
/// `Float` types; the proposal lives in SwiftInferProperties'
/// `SwiftInferProperties/docs/archive/Edge-Case-Biased Generators Kit Proposal.md`.
///
/// The design choice (90/10 mix; hard-coded ratio; 12-entry curated set) is
/// deliberate per §7 of that proposal. Each trial is independently 10%
/// likely to land on an edge case; over N=10 000 trials the binomial
/// distribution puts the edge-case count comfortably in `1000 ± 100`.
public extension Gen where Value == Complex<Double> {

    /// Curated 12-element edge-case set covering the distinct IEEE-754 +
    /// `Complex<Double>` failure modes.
    ///
    /// Order is part of the API: consumers writing counterexample reports
    /// can reference `complexEdgeCases[i]` to identify which class fired.
    /// New entries append to the end; existing indices never shift.
    static var complexEdgeCases: [Complex<Double>] {
        [
            Complex(.nan, .nan),                                // 0
            Complex(.nan, 0),                                   // 1
            Complex(0, .nan),                                   // 2
            Complex(.infinity, 0),                              // 3
            Complex(-.infinity, 0),                             // 4
            Complex(0, .infinity),                              // 5
            Complex(0, -.infinity),                             // 6
            Complex(.infinity, .infinity),                      // 7
            Complex(0, 0),                                      // 8
            Complex(-0.0, 0),                                   // 9
            Complex(.greatestFiniteMagnitude, 0),               // 10
            Complex(.leastNonzeroMagnitude, 0)                  // 11
        ]
    }

    /// 90/10 mix: 90% finite-domain values, 10% drawn uniformly from
    /// `complexEdgeCases`.
    ///
    /// **Implementation note.** The 90/10 split is driven by a single
    /// seeded `Gen<Int>.int(in: 0 ..< 120)` call: tags `0 ..< 12` map to
    /// the corresponding edge case (one tag per entry, so each entry is
    /// equally represented within the 10% slice); tags `12 ..< 120` fall
    /// through to a bounded-magnitude finite Complex value. Per trial each
    /// edge case fires with probability `1/120 ≈ 0.83%`. Over N=10 000
    /// trials the probability of missing any single entry is `(119/120)^N
    /// ≈ 4×10⁻³⁷`, well under the kit's flake threshold.
    ///
    /// **Determinism.** Tag selection (and therefore the edge-vs-finite
    /// decision plus which edge case) is fully seeded by
    /// `swift-property-based`. The finite-path components use
    /// `Double.random(in:)` — non-seeded, mirroring the existing
    /// `Gen<Double>.doubleWithNaN()` kit convention. Coverage and
    /// distribution tests don't depend on the finite-path values.
    ///
    /// **Shrinking.** Edge-case values are already minimal (NaN has no
    /// simpler form); the value itself is the counterexample. Finite-path
    /// values inherit `Gen<Int>.int`'s shrinking behavior on the tag, but
    /// the mapped finite Complex doesn't shrink further.
    static func edgeCaseBiased() -> Generator<Complex<Double>, some SendableSequenceType> {
        let edgeCount = complexEdgeCases.count
        return Gen<Int>.int(in: 0 ..< 120).map { tag -> Complex<Double> in
            if tag < edgeCount {
                return complexEdgeCases[tag]
            }
            // **Deliberately unseeded, and the exception is documented here so a
            // reader hitting the linter's `Non-Injected Nondeterminism` warning
            // finds the reasoning rather than a silence.**
            //
            // `Gen<Double>.doubleWithNaN()` was changed to a fully seeded finite
            // path because there the finite value *is* the sample the always-on
            // laws run against, so a failure on one must be replayable. Here the
            // payload is the 12 curated edge cases; the finite filler exists to
            // dilute them to the 90/10 ratio and is never the interesting input.
            // `determinismOnSeededTagDecisions` pins determinism on the seeded
            // sub-stream — the edge-case projection — which is the guarantee this
            // generator actually offers.
            //
            // Revisit if a law is ever found failing on the finite path: that
            // would make the filler load-bearing and this trade wrong.
            let real = Double.random(in: -1_000_000.0 ... 1_000_000.0)
            let imag = Double.random(in: -1_000_000.0 ... 1_000_000.0)
            return Complex(real, imag)
        }
    }
}
