import Foundation
import Testing
@testable import PropertyLawKit

/// `Every.sequences` — the combinator the design note argued had no
/// `StdlibUnittest` ancestor, and then did not ship.
struct EnumerationSequenceTests {

    private func letters(_ count: Int) -> Enumeration<String> {
        Every.elements("letter", in: (0 ..< count).map { String(UnicodeScalar(97 + $0)!) })
    }

    @Test func countMatchesTheGeometricSeries() {
        for width in 1 ... 4 {
            for maxLength in 0 ... 4 {
                let space = Every.sequences("seq", of: letters(width), upTo: maxLength)
                let expected = (0 ... maxLength).reduce(0) { $0 + Int(pow(Double(width), Double($1))) }
                #expect(space.count == expected, "width \(width), maxLength \(maxLength)")
            }
        }
        // The figure the doc comment quotes.
        #expect(Every.sequences("seq", of: letters(3), upTo: 4).count == 121)
    }

    @Test func unrankingIsABijection() {
        let space = Every.sequences("seq", of: letters(3), upTo: 4)
        let walked = Set(space.indices.map { $0 }.map { space[$0] })
        #expect(walked.count == 121, "a sequence was produced twice")
    }

    @Test func sequencesAreShortestFirstAndStartEmpty() {
        let space = Every.sequences("seq", of: letters(3), upTo: 4)
        #expect(space[0].isEmpty)
        #expect(space.indices.dropLast().allSatisfy { space[$0].count <= space[$0 + 1].count })
        #expect(space.indices.allSatisfy { space.size(of: $0) == space[$0].count })
    }

    @Test func orderIsLexicographicWithinALength() {
        let space = Every.sequences("seq", of: letters(3), upTo: 3)
        let pairs = space.indices.map { space[$0] }.filter { $0.count == 2 }
        #expect(pairs.first == ["a", "a"])
        #expect(pairs.last == ["c", "c"])
        #expect(pairs == pairs.sorted { lhs, rhs in
            for (left, right) in zip(lhs, rhs) where left != right { return left < right }
            return false
        })
    }

    // MARK: - Edges

    @Test func aSingletonAlphabetGivesOneSequencePerLength() {
        let space = Every.sequences("seq", of: letters(1), upTo: 5)
        #expect(space.count == 6)
        #expect(space[5] == Array(repeating: "a", count: 5))
    }

    @Test func maxLengthZeroIsJustTheEmptySequence() {
        let space = Every.sequences("seq", of: letters(3), upTo: 0)
        #expect(space.count == 1)
        #expect(space[0].isEmpty)
    }

    /// An empty alphabet admits the empty sequence and nothing longer, which is
    /// the mathematically right answer rather than an empty space.
    @Test func anEmptyAlphabetStillAdmitsTheEmptySequence() {
        let space = Every.sequences("seq", of: Every.elements("none", in: [String]()), upTo: 4)
        #expect(space.count == 1)
        #expect(space[0].isEmpty)
    }

    /// Closed-form, so a large space costs the same to index at the end as at
    /// the start — 5 actions to length 8 is 488 281 sequences.
    @Test func aLargeSequenceSpaceIsIndexedWithoutBeingMaterialised() {
        let space = Every.sequences("seq", of: letters(5), upTo: 8)
        #expect(space.count == 488_281)
        #expect(space[488_280] == Array(repeating: "e", count: 8))
        #expect(space.size(of: 488_280) == 8)
    }

    /// It composes like every other space: a product of two sequence spaces is
    /// ordered by their summed length.
    @Test func sequenceSpacesCompose() {
        let space = Every.product(
            Every.sequences("left", of: letters(2), upTo: 2),
            Every.sequences("right", of: letters(2), upTo: 2)
        )
        #expect(space.count == 7 * 7)
        #expect(space[0].0.isEmpty && space[0].1.isEmpty)
        #expect(space.indices.dropLast().allSatisfy { space.size(of: $0) <= space.size(of: $0 + 1) })
    }
}
