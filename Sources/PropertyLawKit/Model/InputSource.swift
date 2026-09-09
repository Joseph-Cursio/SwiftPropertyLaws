import PropertyBased

/// Where a law's inputs come from.
///
/// The kit has two kinds, and until now only one of them could reach a law.
/// `.sampled` is the original: random draws judged against `options.budget`,
/// with no denominator — a law that passes has passed on whatever the
/// generator's construction path happened to produce. `.enumerated` walks a
/// bounded space in full, smallest case first.
///
/// The distinction matters most for **conditional** laws, the ones shaped
/// `guard antecedent else { return true }`. Sampled, a zero-application run is
/// uninterpretable: "the generator never built such a case" and "no such case
/// exists" both count zero, and the harness cannot tell them apart. Over a
/// *complete* walk the second reading is the only one available, so a vacuous
/// pass stops being a warning about the generator and becomes a fact about the
/// subject. `Applications.verdict(coverage:)` is where that distinction is
/// drawn.
///
/// Closure-shaped on the `.sampled` side to match the `PropertyBackend` seam —
/// the kit never threads a `Generator` through a driver, so the generator's own
/// `ShrinkSequence` is erased here exactly as it already was. Value-level
/// shrinking stays a separate `shrink:` argument, and `.enumerated` needs none:
/// walking smallest-first leaves nothing to shrink.
package enum InputSource<Value: Sendable>: Sendable {
    case sampled(@Sendable (inout Xoshiro) -> Value)
    case enumerated(Enumeration<Value>)
    /// Random draws **from a bounded space**, keeping the index.
    ///
    /// The middle ground, and the one the plain `Generator` bridge cannot
    /// occupy. `Enumeration.generator` erases the index at the `.map`, so a
    /// failure is the first drawn rather than the smallest, and the run cannot
    /// say what fraction of the space it saw. Keeping the index inside the
    /// driver recovers both — it shrinks toward index 0, which is the smallest
    /// case because spaces are ordered smallest-first, and it counts the
    /// distinct cases it drew against a denominator it knows.
    ///
    /// The index never reaches the law: property closures still receive a bare
    /// `Value`. That is the whole reason this is a source rather than a
    /// generator.
    case sampledFromSpace(Enumeration<Value>)
}

extension InputSource {
    /// Draw from a generator — the shape every existing law entry point uses.
    package static func sampling<Shrinker: SendableSequenceType>(
        _ generator: Generator<Value, Shrinker>
    ) -> InputSource<Value> {
        .sampled { rng in generator.run(using: &rng) }
    }
}
