import DequeModule
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// The gap this space exists to close, measured on both sides.
@Suite("Deque ring-buffer layouts")
struct DequeLayoutTests {

    private func isContiguous(_ deque: Deque<Int>) -> Bool {
        deque.withContiguousStorageIfAvailable { _ in true } ?? false
    }

    /// **The gap.** `withContiguousStorageIfAvailable` is offered for a
    /// contiguous buffer and withheld for a wrapped one, so it is not internal
    /// bookkeeping — it is a branch `Sequence`'s own laws observe.
    @Test("the array construction path reaches exactly one layout")
    func arrayBuiltDequesAreAlwaysContiguous() {
        var rng = Xoshiro(seed: (1, 2, 3, 4))
        let generator = Gen<Int>.int(in: 0 ..< 100).array(of: 0 ... 12).map { Deque($0) }
        var wrapped = 0
        for _ in 0 ..< 1000 where !isContiguous(generator.run(using: &rng)) { wrapped += 1 }
        #expect(wrapped == 0, "expected the array path to produce no wrapped buffers at all")
    }

    /// **The close.** The same laws, over a space whose cases are built rather
    /// than drawn.
    @Test("the layout space reaches wrapped buffers the generator cannot")
    func layoutSpaceReachesWrappedBuffers() {
        let space = DequeLayouts.everyLayout()
        let wrapped = space.indices.filter { !isContiguous(space[$0]) }.count
        #expect(space.count == 107, "6 capacities: 1 + 3 + 6 + 10 + 21 + 66 arrangements")
        #expect(wrapped > 0, "a space that reaches no wrapped layout closes nothing")

    }

    @Test("layouts are ordered smallest deque first")
    func layoutSpaceIsSmallestFirst() {
        let space = DequeLayouts.everyLayout()
        #expect(space[0].isEmpty)
        #expect(space.indices.dropLast().allSatisfy { space[$0].count <= space[$0 + 1].count })
        #expect(space.indices.allSatisfy { space.size(of: $0) == space[$0].count })
    }

    /// Contents depend only on the count, so any two arrangements of one size
    /// are equal as values and differ only in head position. That is what makes
    /// this a test of layout rather than of contents.
    @Test("arrangements of one size are equal as values")
    func sameSizedLayoutsAreEqualValues() {
        let space = DequeLayouts.everyLayout()
        let bySize = Dictionary(grouping: space.indices, by: { space[$0].count })
        for (size, indices) in bySize where size > 1 {
            let values = Set(indices.map { Array(space[$0]) })
            #expect(values.count == 1, "size \(size) produced differing contents")
        }
    }

    /// The bridge: a structured space driving a suite that has no walked entry.
    @Test("the layout space drives the Sequence and Collection suites")
    func layoutSpaceDrivesExistingSuites() async throws {
        let generator = DequeLayouts.everyLayout().generator
        try await checkSequencePropertyLaws(using: generator, options: LawCheckOptions(budget: .sanity))
        try await checkCollectionPropertyLaws(using: generator, options: LawCheckOptions(budget: .sanity))
    }

    /// **The carrier form, and why it is not the same as the bridge above.**
    ///
    /// `checkSequencePropertyLaws(using: space.generator)` draws layouts as
    /// inputs: 1 000 trials spread over 107 arrangements, so each law *probably*
    /// sees every layout — coupon-collector says about 578 draws suffice — and
    /// **cannot say that it did**. `checkEveryCarrier` runs the whole suite once
    /// per layout, so every law meets every arrangement by construction, and the
    /// result reports the denominator.
    ///
    /// The cost is the reason it needs its own budget: 107 carriers at
    /// `.sanity` is 10 700 evaluations per law, against 1 000 for the bridge.
    @Test("every law meets every layout, and the run says so")
    func everyLawMeetsEveryLayout() async throws {
        let layouts = DequeLayouts.everyLayout()
        let results = try await checkEveryCarrier(of: layouts) { deque, options in
            try await checkBidirectionalCollectionPropertyLaws(
                using: Gen.always(deque),
                options: options,
                laws: .all
            )
        }
        #expect(results.allSatisfy { $0.coverage?.spaceSize == 107 })
        #expect(results.allSatisfy { $0.coverage?.isComplete == true },
                "every layout must be reached by every law, not merely likely to be")
        #expect(results.allSatisfy { !$0.isViolation })
        #expect(results.map(\.protocolLaw).contains("BidirectionalCollection.indexBeforeAfterRoundTrip"))
    }
}
