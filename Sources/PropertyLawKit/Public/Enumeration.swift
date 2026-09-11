import PropertyBased

/// A contiguous run of cases sharing one size, inside an ``Enumeration``.
///
/// Deliberately not nested inside `Enumeration`: it carries no element type, and
/// nesting it inside the generic would have made the buckets of an
/// `Enumeration<A>` a different type from those of an `Enumeration<B>` — so
/// ``Enumeration/map(_:)``, which changes the element type and moves nothing,
/// could not have reused them.
public struct EnumerationBucket: Sendable, Hashable {
    /// The size every case in this run has. Ascends across a space's buckets.
    public let size: Int
    /// Index of this run's first case.
    public let start: Int
    /// How many cases the run holds. Always positive.
    public let count: Int

    public init(size: Int, start: Int, count: Int) {
        self.size = size
        self.start = start
        self.count = count
    }

    /// The half-open range of indices this run holds.
    public var indices: Range<Int> { start ..< (start + count) }

    /// The bucket in `buckets` holding `index`, or `nil` when none does.
    ///
    /// **Total, and that is the point of it being here rather than inside
    /// ``Enumeration``.** The search is over `[EnumerationBucket]` and an `Int`; it has
    /// nothing to do with an element type, and welding it to the generic meant it could
    /// only ever be exercised through whatever bucket layouts the `Every.*` constructors
    /// happen to produce — never an empty array, never a layout with a one-case bucket
    /// between two large ones, never a gap. A free function over the two things it
    /// actually reads can be quantified over every layout instead.
    ///
    /// Answers `nil` rather than trapping, so the caller names its own boundary policy at
    /// the call site: ``Enumeration/bucket(containing:)`` keeps its precondition, because
    /// an out-of-range index there is a programmer error and a space that answered anyway
    /// would report a failing case as minimal when it is not.
    ///
    /// Binary search rather than a scan because `subsets(of: 20)` has 21 buckets over a
    /// million cases and ``Enumeration/size(of:)`` is called once per walked case.
    /// ``EnumerationBucket`` makes no claim that `buckets` is well formed — the layout
    /// invariant is `Enumeration.init`'s to enforce — so this is stated over *sorted*
    /// starts alone, which is the weakest precondition the search needs.
    public static func containing(_ index: Int, in buckets: [EnumerationBucket]) -> EnumerationBucket? {
        guard buckets.isEmpty == false else { return nil }
        var low = 0
        var high = buckets.count - 1
        // The interval must shrink on every iteration, and `(low + high + 1) / 2` is what
        // guarantees it: with `high == low + 1` the midpoint rounds *up*, so `low = middle`
        // advances. Round down instead and that step leaves the interval unchanged forever.
        //
        // Bounding the loop makes that a **checked** claim rather than an emergent one, and the
        // failure it converts is the worst kind to test for. Measured both ways against the
        // rounded-down midpoint: with this cap the suite crashes here and reports a failure;
        // without it the suite **hangs**, and a hanging test reports nothing at all.
        //
        // Removing the cap on its own is therefore a surviving mutant, correctly — with the
        // midpoint right the loop always converges and the cap never fires. It is defended by
        // the pair, not by a mutant of its own, and `theCapIsNotTighterThanTheSearchNeeds`
        // guards the other direction.
        var remainingSteps = Int.bitWidth - buckets.count.leadingZeroBitCount + 1
        while low < high {
            precondition(
                remainingSteps > 0,
                "EnumerationBucket.containing: search did not converge over \(buckets.count) buckets"
            )
            remainingSteps -= 1
            let middle = (low + high + 1) / 2
            if buckets[middle].start <= index { low = middle } else { high = middle - 1 }
        }
        let candidate = buckets[low]
        return candidate.indices.contains(index) ? candidate : nil
    }
}

/// A bounded input space that can be walked in full, smallest case first.
///
/// The kit's other input source is `Generator` — an unbounded stream of random
/// draws, judged against a `TrialBudget`. An `Enumeration` is the other kind: a
/// *finite* set of cases with a known size, a defined order, and an address for
/// every case. The difference is not sample size. A budget of ten thousand
/// draws is ten thousand samples from whatever distribution the generator's
/// construction path happens to produce; an enumeration of 512 cases is all 512
/// of them, and says so.
///
/// ## Why an indexed value rather than a nested callback
///
/// `StdlibUnittest`'s combinators nest — `withEvery("a", in: 0 ..< 5) { a in
/// withEvery(…) }` — so the case that failed is identified by the path taken
/// through a call tree, which is why that apparatus needs a label stack to
/// accumulate the path as it walks. Indexing computes the address instead: case
/// `n` has an address whether or not anything walked to it, so no stack is
/// needed, a sampled case still reports where in the full space it came from,
/// and composition is arithmetic.
///
/// ## The ordering invariant, which is the whole point
///
/// `buckets` states the order rather than leaving it to be assumed: cases are
/// grouped into contiguous runs of equal `size`, and the runs ascend. That is
/// what makes the *first* failing case the *smallest* failing case, and it is
/// why this type ships no shrinker — enumerate smallest-first and there is
/// nothing left to shrink.
///
/// `size` means whatever the constructor says it means (a range's length, a
/// subset's cardinality) and is `0` throughout for a space whose elements have
/// no size notion, such as ``elements(_:in:)`` over an arbitrary carrier. A space
/// with one bucket is ordered exactly as it was given.
public struct Enumeration<Element: Sendable>: Sendable {

    /// Ascending by `size`, contiguous, covering `0 ..< count` exactly.
    ///
    /// Public because it is the ordering contract, not an implementation
    /// detail: a caller can read the size distribution off it, and a combinator
    /// outside this file can compose spaces without re-deriving it.
    public let buckets: [EnumerationBucket]

    /// Size of the space this was derived from, before any ``prefix(_:)``.
    /// Equal to ``count`` when nothing was truncated. Carried so a truncated
    /// walk can report the shortfall rather than claim completeness.
    public let fullCount: Int

    private let build: @Sendable (Int) -> Element
    private let describe: @Sendable (Int) -> String

    /// Number of cases this enumeration will walk.
    public var count: Int {
        guard let last = buckets.last else { return 0 }
        return last.start + last.count
    }

    /// Whether this enumeration covers the whole space it was derived from.
    public var isComplete: Bool { count == fullCount }

    /// - Parameters:
    ///   - buckets: must be size-ascending, contiguous from 0, each non-empty.
    ///     Violations are programmer errors and trap rather than being
    ///     tolerated: a space that misrepresents its own order would report a
    ///     failing case as minimal when it is not.
    ///   - fullCount: size before truncation; defaults to the bucket total.
    public init(
        buckets: [EnumerationBucket],
        fullCount: Int? = nil,
        build: @escaping @Sendable (Int) -> Element,
        describe: @escaping @Sendable (Int) -> String
    ) {
        var expectedStart = 0
        var previousSize: Int?
        for bucket in buckets {
            precondition(bucket.count > 0, "Enumeration: empty size bucket at index \(bucket.start)")
            precondition(
                bucket.start == expectedStart,
                "Enumeration: bucket starting at \(bucket.start) leaves a gap; expected \(expectedStart)"
            )
            if let previousSize {
                precondition(
                    bucket.size > previousSize,
                    "Enumeration: bucket sizes must strictly ascend; \(bucket.size) follows \(previousSize)"
                )
            }
            previousSize = bucket.size
            expectedStart += bucket.count
        }
        self.buckets = buckets
        self.fullCount = fullCount ?? expectedStart
        self.build = build
        self.describe = describe
        precondition(
            self.fullCount >= expectedStart,
            "Enumeration: fullCount \(self.fullCount) is smaller than the \(expectedStart) cases held"
        )
    }

    /// The case at `index`.
    public subscript(index: Int) -> Element {
        precondition(indices.contains(index), "Enumeration: index \(index) outside 0 ..< \(count)")
        return build(index)
    }

    /// Where case `index` sits in the space, as text — the counterexample a
    /// failure reports, and the reason no label stack is needed.
    public func address(of index: Int) -> String {
        precondition(indices.contains(index), "Enumeration: index \(index) outside 0 ..< \(count)")
        return describe(index)
    }

    /// The size of case `index`, per this space's size notion.
    public func size(of index: Int) -> Int {
        bucket(containing: index).size
    }

    public var indices: Range<Int> { 0 ..< count }

    /// The bucket holding `index` — `buckets` is ascending and contiguous, so the search
    /// in ``EnumerationBucket/containing(_:in:)`` applies.
    ///
    /// The kernel answers `nil` for an index no bucket holds; here that cannot happen for
    /// an index the precondition admits, because `init` has established that the buckets
    /// tile `0 ..< count` with no gap. The `nil` arm is therefore unreachable and traps
    /// rather than being given a fallback — a space that answered anyway would report a
    /// failing case as minimal when it is not.
    func bucket(containing index: Int) -> EnumerationBucket {
        precondition(indices.contains(index), "Enumeration: index \(index) outside 0 ..< \(count)")
        guard let bucket = EnumerationBucket.containing(index, in: buckets) else {
            preconditionFailure("Enumeration: no bucket holds in-range index \(index)")
        }
        return bucket
    }

    /// The first `maxCases` cases — the smallest ones, given the ordering
    /// invariant. The result remembers the original ``fullCount``, so a walk
    /// over it reports partial coverage instead of claiming to have seen
    /// everything.
    public func prefix(_ maxCases: Int) -> Enumeration<Element> {
        precondition(maxCases >= 0, "Enumeration.prefix: negative maxCases \(maxCases)")
        guard maxCases < count else { return self }
        var kept: [EnumerationBucket] = []
        var taken = 0
        for bucket in buckets where taken < maxCases {
            let room = maxCases - taken
            let take = min(bucket.count, room)
            kept.append(EnumerationBucket(size: bucket.size, start: bucket.start, count: take))
            taken += take
        }
        return Enumeration(buckets: kept, fullCount: fullCount, build: build, describe: describe)
    }

    /// Transform each case, keeping the order, the sizes and the addresses.
    /// Position is what an address names, and mapping does not move anything.
    public func map<Mapped: Sendable>(
        _ transform: @escaping @Sendable (Element) -> Mapped
    ) -> Enumeration<Mapped> {
        let build = self.build
        return Enumeration<Mapped>(
            buckets: buckets,
            fullCount: fullCount,
            build: { transform(build($0)) },
            describe: describe
        )
    }
}

extension Enumeration {

    /// Draw from this space at random, as an ordinary kit `Generator`.
    ///
    /// The escape hatch for a space too large to walk, and the door into the
    /// forty-odd suites that have no `overEvery:` entry point — `Equatable`,
    /// `Hashable`, `Collection` and the rest all take a `Generator`, so this is
    /// how a structured space reaches them:
    ///
    /// ```swift
    /// try await checkSequencePropertyLaws(using: dequeLayouts.generator)
    /// ```
    ///
    /// ## What this gives up, stated plainly
    ///
    /// **No minimality and no shrinking.** The kit's per-law shrinker is
    /// value-level (`LawCheck.shrink`) and the kit deliberately never threads a
    /// `Generator` through a driver, so the index shrinker in this type's
    /// signature is *not consulted*. A failure here is the first one drawn, not
    /// the smallest one that exists. Measured on a 1 024-case space: walking
    /// reports the minimal `[0, 1, 2]`, this reports whatever came up — in that
    /// run, `[0, 3, 4, 8, 9]`.
    ///
    /// **No coverage denominator.** A sampled run reports `nil` coverage like
    /// any other, so it cannot say what fraction of the space it saw.
    ///
    /// Prefer ``checkEveryCase(of:law:tier:options:satisfies:)`` or a suite's
    /// `overEvery:` entry where one exists. Reach for this when the space is too
    /// large to walk, or when the suite you need has no walked entry.
    ///
    /// ## What it still gives
    ///
    /// **Structural reach.** The point of a space is that its cases are defined
    /// rather than constructed, so it reaches configurations a generator built
    /// from a construction path never produces — not rarely, never. That
    /// property survives sampling intact, and it is the reason this is worth
    /// having despite the two paragraphs above.
    public var generator: Generator<Element, Shrink.Integer<Int>> {
        precondition(count > 0, "Enumeration.generator: cannot draw from an empty space")
        let space = self
        return Gen<Int>.int(in: 0 ..< count).map { space[$0] }
    }
}
