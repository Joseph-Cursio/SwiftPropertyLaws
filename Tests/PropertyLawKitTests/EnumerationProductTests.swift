import Testing
@testable import PropertyLawKit

/// Summed-size product ordering. The design note that proposed it recorded it
/// as *reasoned, not built*, and said it should be checked against a
/// materialised brute-force ordering before being relied on. That check is
/// `productWalkMatchesABruteForceSummedSizeOrdering`; the rest of this suite
/// exists so a regression in the unranking cannot pass as a reordering.
struct EnumerationProductTests {

    /// The ordering, computed the slow obvious way: every pair, sorted by summed
    /// size with ties broken by the factors' own indices. If the closed-form
    /// unranking and this disagree, the closed-form one is wrong.
    private func bruteForceOrder<First, Second>(
        _ first: Enumeration<First>,
        _ second: Enumeration<Second>
    ) -> [(Int, Int)] {
        var pairs: [(Int, Int)] = []
        for left in first.indices {
            for right in second.indices { pairs.append((left, right)) }
        }
        return pairs.sorted { lhs, rhs in
            let lhsSize = first.size(of: lhs.0) + second.size(of: lhs.1)
            let rhsSize = first.size(of: rhs.0) + second.size(of: rhs.1)
            if lhsSize != rhsSize { return lhsSize < rhsSize }
            if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
            return lhs.1 < rhs.1
        }
    }

    @Test func productWalkMatchesABruteForceSummedSizeOrdering() {
        let ranges = Every.ranges("range", upTo: 4)
        let subsets = Every.subsets("subset", of: 4)
        let space = Every.product(ranges, subsets)
        let expected = bruteForceOrder(ranges, subsets)
        #expect(space.count == expected.count)
        for index in space.indices {
            let (left, right) = expected[index]
            let (walkedRange, walkedSubset) = space[index]
            #expect(walkedRange == ranges[left], "case \(index) took the wrong first factor")
            #expect(walkedSubset == subsets[right], "case \(index) took the wrong second factor")
            #expect(space.address(of: index) == "\(ranges.address(of: left)) / \(subsets.address(of: right))")
        }
    }

    @Test func productSizesAscendAndEqualTheSummedSize() {
        let space = Every.product(Every.ranges("range", upTo: 3), Every.subsets("subset", of: 3))
        #expect(space.indices.dropLast().allSatisfy { space.size(of: $0) <= space.size(of: $0 + 1) })
        #expect(space.indices.allSatisfy { space.size(of: $0) == space[$0].0.count + space[$0].1.count })
        #expect(space[0].0.isEmpty && space[0].1.isEmpty, "the first case must be the smallest one")
    }

    @Test func productIsABijectionOntoThePairs() {
        let ranges = Every.ranges("range", upTo: 3)
        let subsets = Every.subsets("subset", of: 3)
        let space = Every.product(ranges, subsets)
        #expect(space.count == ranges.count * subsets.count)
        var seen = Set<String>()
        for index in space.indices {
            let pair = space[index]
            #expect(seen.insert("\(pair.0)|\(pair.1)").inserted, "case \(index) is a duplicate")
        }
        #expect(seen.count == space.count)
    }

    /// The design decision, pinned. Summed-size and row-major are not two
    /// spellings of one order — they disagree about which case comes first, and
    /// a change that quietly reverted to row-major would fail here.
    @Test func summedSizeOrderingIsNotRowMajorOrdering() {
        let ranges = Every.ranges("range", upTo: 4)
        let subsets = Every.subsets("subset", of: 5)
        let space = Every.product(ranges, subsets)
        var rowMajor: [(Int, Int)] = []
        for left in ranges.indices {
            for right in subsets.indices { rowMajor.append((left, right)) }
        }
        let disagreements = space.indices.filter { index in
            let (left, right) = rowMajor[index]
            let walked = space[index]
            return !(walked.0 == ranges[left] && walked.1 == subsets[right])
        }
        #expect(!disagreements.isEmpty, "summed-size ordering collapsed to row-major")
    }

    @Test func productWithAnEmptyFactorIsEmpty() {
        let space = Every.product(Every.elements("nothing", in: [Int]()), Every.subsets("subset", of: 3))
        #expect(space.count == 0)
        #expect(space.buckets.isEmpty)
    }

    @Test func productOfSizelessSpacesPreservesRowOrder() {
        // Neither factor declares a size, so there is one rectangle and the
        // order is exactly the order the factors were given in.
        let first = Every.elements("left", in: ["a", "b"])
        let second = Every.elements("right", in: [1, 2, 3])
        let space = Every.product(first, second)
        #expect(space.count == 6)
        #expect(space.indices.map { "\(space[$0].0)\(space[$0].1)" } == ["a1", "a2", "a3", "b1", "b2", "b3"])
    }

    @Test func productCarriesFullCountThroughTruncation() {
        let space = Every.product(
            Every.subsets("left", of: 4).prefix(4),
            Every.subsets("right", of: 4)
        )
        #expect(space.count == 4 * 16)
        #expect(space.fullCount == 16 * 16)
        #expect(space.isComplete == false)
    }

    // MARK: - triples

    @Test func triplesWalkTheWholeCube() {
        let carrier = Every.elements("value", in: 0 ..< 5)
        let space = Every.triples(of: carrier)
        #expect(space.count == 125)
        var seen = Set<[Int]>()
        for index in space.indices {
            let triple = space[index]
            #expect(seen.insert([triple.first, triple.second, triple.third]).inserted)
        }
        #expect(seen.count == 125, "triples must reach every ordered triple exactly once")
    }

    @Test func tripleAddressesNameAllThreePositions() {
        let space = Every.triples(of: Every.elements("value", in: ["x", "y"]))
        #expect(space.count == 8)
        #expect(space.address(of: 0) == "value=x / value=x / value=x")
        #expect(space.address(of: 7) == "value=y / value=y / value=y")
    }
}
