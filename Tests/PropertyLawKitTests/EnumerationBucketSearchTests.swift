@testable import PropertyLawKit
import Testing

/// Laws over ``EnumerationBucket/containing(_:in:)`` — the index-to-bucket search that
/// ``Enumeration/size(of:)`` calls once per walked case.
///
/// **Why this is a suite rather than one assertion.** The search used to live inside
/// `Enumeration<Element>`, so reaching it meant building a whole space with a `build` and a
/// `describe` closure, and the only layouts reachable were the ones `Every.elements`,
/// `.ranges`, `.subsets`, `.product` and `.sequences` happen to produce. The single test that
/// existed ran it over `subsets(of: 9)` — one binomial layout, ten buckets — and checked
/// containment. Nothing reached an empty array, a layout whose first bucket holds one case, a
/// gap, or an index outside every bucket.
///
/// Lifted to a function of `([EnumerationBucket], Int)` those are all constructible, and the
/// space of small layouts is small enough to **walk** rather than sample: every composition of
/// 0...4 buckets with counts 1...3 is 121 layouts, and every index from two before the start to
/// one past the end of each is 1,336 checks. So these say *holds*, not *held for a thousand
/// draws*, and the count is asserted so a walk that quietly stopped covering the space shows up.
@Suite("The bucket search")
struct EnumerationBucketSearchTests {

    // MARK: - The space

    /// Every contiguous layout of `bucketCount` buckets whose counts are drawn from
    /// `1...maxCount`, sizes ascending — the shape `Enumeration.init` enforces.
    private static func layouts(bucketCount: Int, maxCount: Int) -> [[EnumerationBucket]] {
        guard bucketCount > 0 else { return [[]] }
        return layouts(bucketCount: bucketCount - 1, maxCount: maxCount).flatMap { shorter in
            (1 ... maxCount).map { count in
                let start = shorter.last.map { $0.start + $0.count } ?? 0
                return shorter + [EnumerationBucket(size: shorter.count, start: start, count: count)]
            }
        }
    }

    /// Every well-formed layout of up to four buckets, plus the empty one.
    private static var everyLayout: [[EnumerationBucket]] {
        (0 ... 4).flatMap { layouts(bucketCount: $0, maxCount: 3) }
    }

    /// The obvious correct implementation, against which the binary search is judged.
    private func linearScan(_ index: Int, _ buckets: [EnumerationBucket]) -> EnumerationBucket? {
        buckets.first { $0.indices.contains(index) }
    }

    /// One past each end, so the boundary is inside the walk rather than a separate case.
    private func probes(for buckets: [EnumerationBucket]) -> ClosedRange<Int> {
        let total = buckets.last.map { $0.start + $0.count } ?? 0
        return -2 ... (total + 1)
    }

    // MARK: - Laws

    /// **The model law, and the one that catches an off-by-one.** A binary search either
    /// agrees with a scan everywhere or it is wrong; there is no third state.
    @Test func agreesWithALinearScanOnEveryLayoutAndEveryIndex() {
        var checked = 0
        for buckets in Self.everyLayout {
            for index in probes(for: buckets) {
                #expect(
                    EnumerationBucket.containing(index, in: buckets) == linearScan(index, buckets),
                    "layout \(buckets.map(\.count)) index \(index)"
                )
                checked += 1
            }
        }
        // The denominator, so a walk that quietly stopped covering the space is visible.
        // 3^k layouts for k buckets, k in 0...4, is 121 layouts; each contributes its own
        // `total + 4` probes. 4 + 18 + 72 + 270 + 972 = 1_336.
        #expect(checked == 1_336)
    }

    /// **Totality.** Answers for every layout and every index, including the empty layout and
    /// indices outside it. The old method could not say this: it traps on an out-of-range index
    /// by design, and would have subscripted an empty array.
    @Test func answersForEveryLayoutIncludingEmptyAndOutOfRange() {
        #expect(EnumerationBucket.containing(0, in: []) == nil)
        #expect(EnumerationBucket.containing(-1, in: []) == nil)
        #expect(EnumerationBucket.containing(Int.max, in: []) == nil)

        for buckets in Self.everyLayout where buckets.isEmpty == false {
            let total = buckets.last!.start + buckets.last!.count
            #expect(EnumerationBucket.containing(-1, in: buckets) == nil)
            #expect(EnumerationBucket.containing(total, in: buckets) == nil)
        }
    }

    /// **Soundness.** A returned bucket really holds the index. Vacuous if the search returned
    /// `nil` everywhere, which is why the completeness law below is stated separately.
    @Test func aReturnedBucketHoldsTheIndex() {
        for buckets in Self.everyLayout {
            for index in probes(for: buckets) {
                guard let found = EnumerationBucket.containing(index, in: buckets) else { continue }
                #expect(found.indices.contains(index))
                #expect(buckets.contains(found))
            }
        }
    }

    /// **Completeness.** Every in-range index finds a bucket. Paired with soundness above, this
    /// is what makes the pair a decision rather than a one-sided check.
    @Test func everyInRangeIndexFindsABucket() {
        for buckets in Self.everyLayout where buckets.isEmpty == false {
            let total = buckets.last!.start + buckets.last!.count
            for index in 0 ..< total {
                #expect(EnumerationBucket.containing(index, in: buckets) != nil, "index \(index)")
            }
        }
    }

    /// **The layout tiles, so the answer is unique.** Not a property of the search — a property
    /// of the shape `Enumeration.init` enforces — and the search's completeness rests on it, so
    /// it is stated rather than assumed.
    @Test func theLayoutsWalkedHereTileTheirRangeExactly() {
        for buckets in Self.everyLayout where buckets.isEmpty == false {
            let total = buckets.last!.start + buckets.last!.count
            let covered = buckets.flatMap { Array($0.indices) }
            #expect(covered == Array(0 ..< total), "layout \(buckets.map(\.count))")
        }
    }

    // MARK: - The boundary the old shape could not reach

    /// A one-case bucket between two larger ones — the layout where a `middle` computed with
    /// `(low + high) / 2` instead of `(low + high + 1) / 2` fails to converge or overshoots.
    @Test func findsASingleCaseBucketBetweenLargerNeighbours() {
        let buckets = [
            EnumerationBucket(size: 0, start: 0, count: 5),
            EnumerationBucket(size: 1, start: 5, count: 1),
            EnumerationBucket(size: 2, start: 6, count: 5)
        ]
        #expect(EnumerationBucket.containing(5, in: buckets) == buckets[1])
        #expect(EnumerationBucket.containing(4, in: buckets) == buckets[0])
        #expect(EnumerationBucket.containing(6, in: buckets) == buckets[2])
    }

    /// A single bucket — `high` starts at `0`, so the loop never runs.
    @Test func findsTheOnlyBucket() {
        let only = [EnumerationBucket(size: 3, start: 0, count: 4)]
        #expect(EnumerationBucket.containing(0, in: only) == only[0])
        #expect(EnumerationBucket.containing(3, in: only) == only[0])
        #expect(EnumerationBucket.containing(4, in: only) == nil)
    }

    // MARK: - The caller's policy is still the caller's

    /// `Enumeration.bucket(containing:)` keeps its precondition rather than adopting the
    /// kernel's `nil`, and `size(of:)` goes through it — so a space still refuses to answer for
    /// an index it does not hold, which is what keeps "the first failure is the smallest" true.
    @Test func theSpaceStillAgreesWithTheKernelOnEveryIndexItHolds() {
        let space = Every.subsets("subset", of: 9)
        for index in space.indices {
            let viaSpace = space.bucket(containing: index)
            #expect(EnumerationBucket.containing(index, in: space.buckets) == viaSpace)
            #expect(space.size(of: index) == viaSpace.size)
        }
        // And a truncated space, whose buckets no longer cover `fullCount`.
        let truncated = space.prefix(100)
        #expect(truncated.isComplete == false)
        for index in truncated.indices {
            #expect(EnumerationBucket.containing(index, in: truncated.buckets) != nil)
        }
        #expect(EnumerationBucket.containing(truncated.count, in: truncated.buckets) == nil)
    }

    // MARK: - The step cap

    /// The cap exists to turn a non-terminating search into a reported failure rather than a
    /// hang. Measured against the rounded-down midpoint: **with** the cap the suite crashes and
    /// reports; **without** it the suite hangs and reports nothing.
    ///
    /// This guards the other direction — that the cap is not so tight it fires on a correct
    /// search over a large layout. `ceil(log2(n)) + 1` is the bound a halving search needs, and
    /// a thousand buckets is more than any `Every.*` constructor produces.
    @Test func theCapIsNotTighterThanTheSearchNeeds() {
        let many = (0 ..< 1_000).map { EnumerationBucket(size: $0, start: $0 * 2, count: 2) }
        for index in [0, 1, 999, 1_000, 1_001, 1_998, 1_999] {
            #expect(EnumerationBucket.containing(index, in: many)?.indices.contains(index) == true)
        }
        #expect(EnumerationBucket.containing(2_000, in: many) == nil)
    }
}
