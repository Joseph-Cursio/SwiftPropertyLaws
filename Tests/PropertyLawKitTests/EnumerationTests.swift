import Testing
@testable import PropertyLawKit

/// The space type and its base constructors. The bucket invariant is the
/// ordering contract, so it is asserted directly on every constructor rather
/// than inferred from a walk coming out in a pleasing order.
struct EnumerationTests {

    /// Buckets must ascend by size, be contiguous from 0, be non-empty, and
    /// cover `count` exactly. Every claim this type makes about minimality
    /// rests on this holding.
    private func assertBucketInvariant<Element>(
        _ space: Enumeration<Element>,
        _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var expectedStart = 0
        var previousSize: Int?
        for bucket in space.buckets {
            #expect(bucket.count > 0, "\(label): empty bucket", sourceLocation: sourceLocation)
            #expect(bucket.start == expectedStart, "\(label): gap at \(bucket.start)", sourceLocation: sourceLocation)
            if let previousSize {
                #expect(bucket.size > previousSize, "\(label): sizes not ascending", sourceLocation: sourceLocation)
            }
            previousSize = bucket.size
            expectedStart += bucket.count
        }
        #expect(expectedStart == space.count, "\(label): buckets do not cover count", sourceLocation: sourceLocation)
    }

    // MARK: - ranges

    @Test func rangesCountMatchesTheClosedForm() {
        for bound in 0 ... 8 {
            let space = Every.ranges("range", upTo: bound)
            #expect(space.count == (bound + 1) * (bound + 2) / 2)
            assertBucketInvariant(space, "ranges(\(bound))")
        }
    }

    @Test func rangesIsABijectionOntoItsSubranges() {
        let space = Every.ranges("range", upTo: 6)
        let walked = Set(space.indices.map { space[$0] })
        #expect(walked.count == space.count, "unranking produced a duplicate")
        // 28 subranges of 0..<6, including one empty range per position.
        #expect(walked.count == 28)
    }

    @Test func rangesAreShortestFirstAndStartEmpty() {
        let space = Every.ranges("range", upTo: 5)
        #expect(space[0].isEmpty)
        #expect(space.indices.dropLast().allSatisfy { space[$0].count <= space[$0 + 1].count })
        #expect(space.indices.allSatisfy { space.size(of: $0) == space[$0].count })
    }

    // MARK: - subsets

    @Test func subsetsAreABijectionOntoThePowerSet() {
        let space = Every.subsets("subset", of: 8)
        #expect(space.count == 256)
        let walked = Set(space.indices.map { space[$0] })
        #expect(walked.count == 256, "unranking produced a duplicate")
        assertBucketInvariant(space, "subsets(8)")
    }

    @Test func subsetsAreCardinalityAscendingAndStartEmpty() {
        let space = Every.subsets("subset", of: 7)
        #expect(space[0].isEmpty)
        #expect(space.indices.dropLast().allSatisfy { space[$0].count <= space[$0 + 1].count })
        #expect(space.indices.allSatisfy { space.size(of: $0) == space[$0].count })
    }

    @Test func subsetsAreLexicographicWithinACardinality() {
        let space = Every.subsets("subset", of: 5)
        // The three-element subsets, in the order the space walks them.
        let triples = space.indices.map { space[$0] }.filter { $0.count == 3 }
        #expect(triples.first == [0, 1, 2])
        #expect(triples == triples.sorted { lhs, rhs in
            for (left, right) in zip(lhs, rhs) where left != right { return left < right }
            return false
        })
    }

    /// Closed-form unranking is what makes composition usable. A space with a
    /// million cases must cost the same to index near the end as at the start,
    /// because nothing was materialised.
    @Test func aLargeSpaceIsIndexedWithoutBeingMaterialised() {
        let space = Every.subsets("subset", of: 20)
        #expect(space.count == 1_048_576)
        #expect(space[1_048_575] == Array(0 ..< 20), "the last case is the full set")
        #expect(space[0].isEmpty)
        #expect(space.size(of: 1_048_575) == 20)
    }

    // MARK: - elements

    @Test func elementsPreserveTheGivenOrderAndDeclareNoSize() {
        let space = Every.elements("letter", in: ["c", "a", "b"])
        #expect(space.count == 3)
        #expect(space.indices.map { space[$0] } == ["c", "a", "b"])
        // No size notion: one bucket, size 0 throughout.
        #expect(space.buckets.count == 1)
        #expect(space.buckets.first?.size == 0)
        #expect(space.address(of: 1) == "letter=a")
    }

    @Test func elementsWithASizeReorderToHonourTheInvariant() {
        let space = Every.elements("word", in: ["ccc", "a", "bb"], size: { $0.count })
        #expect(space.indices.map { space[$0] } == ["a", "bb", "ccc"])
        #expect(space.buckets.map(\.size) == [1, 2, 3])
        assertBucketInvariant(space, "elements(size:)")
    }

    @Test func elementsBreakSizeTiesByGivenOrder() {
        let space = Every.elements("word", in: ["bb", "aa", "c"], size: { $0.count })
        // "c" is smaller; "bb" and "aa" tie and keep the order they arrived in.
        #expect(space.indices.map { space[$0] } == ["c", "bb", "aa"])
    }

    @Test func elementsOverAnEmptyCollectionIsAnEmptySpace() {
        let space = Every.elements("nothing", in: [Int]())
        #expect(space.count == 0)
        #expect(space.buckets.isEmpty)
        #expect(space.indices.isEmpty)
    }

    // MARK: - prefix and map

    @Test func prefixTruncatesButRemembersTheFullSpace() {
        let space = Every.subsets("subset", of: 10).prefix(100)
        #expect(space.count == 100)
        #expect(space.fullCount == 1024)
        #expect(space.isComplete == false)
        assertBucketInvariant(space, "prefix(100)")
        // Truncation keeps the smallest cases, so the empty set survives.
        #expect(space[0].isEmpty)
    }

    @Test func prefixLongerThanTheSpaceIsTheSpace() {
        let space = Every.subsets("subset", of: 4).prefix(999)
        #expect(space.count == 16)
        #expect(space.isComplete)
    }

    @Test func mapKeepsOrderSizesAndAddresses() {
        let base = Every.subsets("subset", of: 5)
        let mapped = base.map { $0.count }
        #expect(mapped.count == base.count)
        #expect(mapped.buckets == base.buckets)
        #expect(mapped.indices.allSatisfy { mapped[$0] == base[$0].count })
        #expect(mapped.address(of: 7) == base.address(of: 7))
    }

    @Test func sizeLookupAgreesWithTheBucketHolding() {
        let space = Every.subsets("subset", of: 9)
        for index in space.indices {
            let bucket = space.bucket(containing: index)
            #expect(space.size(of: index) == bucket.size)
            #expect(index >= bucket.start && index < bucket.start + bucket.count)
        }
    }
}
