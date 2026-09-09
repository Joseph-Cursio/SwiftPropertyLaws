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
}

extension InputSource {
    /// Draw from a generator — the shape every existing law entry point uses.
    package static func sampling<Shrinker: SendableSequenceType>(
        _ generator: Generator<Value, Shrinker>
    ) -> InputSource<Value> {
        .sampled { rng in generator.run(using: &rng) }
    }
}
