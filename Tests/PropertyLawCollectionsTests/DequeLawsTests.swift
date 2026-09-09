import DequeModule
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// M1 law runs for `Deque<Int>` — the protocol-richest swift-collections
/// type. Follows the discovery plugin's most-specific-per-chain convention:
/// one `.all` run for the RandomAccess → Bidirectional → Collection →
/// Sequence → Iterator chain, `.ownOnly` for the independent sibling
/// refinements (Mutable, RangeReplaceable), and Hashable `.all` covering
/// Equatable.
struct DequeLawsTests {

    @Test func dequePassesRandomAccessCollectionChain() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(names.contains("BidirectionalCollection.indexBeforeAfterRoundTrip"))
        #expect(names.contains("RandomAccessCollection.distanceConsistency"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesMutableCollectionLaws() async throws {
        let results = try await checkMutableCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesRangeReplaceableCollectionLaws() async throws {
        let results = try await checkRangeReplaceableCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains { $0.hasPrefix("Equatable.") })
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Deque<Int>.self,
            using: Gen<Deque<Int>>.smallIntDeque(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    // MARK: - The same chain, over every ring-buffer layout

    /// **Every run above draws from `smallIntDeque`, which builds each deque as
    /// `Deque(array)` — and that path produced 1 000 contiguous buffers and zero
    /// wrapped ones over 1 000 draws.** So the whole file, at any budget, has
    /// only ever exercised one of the layouts a `Deque` can be in.
    ///
    /// A layout cannot be drawn, only built, so closing that needs a space
    /// rather than a wider generator. `DequeLayouts.everyLayout()` is 107
    /// arrangements of which 59 are wrapped, and these two runs put the index
    /// arithmetic that walks a wrapped buffer under the same laws for the first
    /// time.
    @Test func dequePassesTheCollectionChainOverEveryLayout() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: DequeLayouts.everyLayout().generator,
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func dequePassesMutationLawsOverEveryLayout() async throws {
        let layouts = DequeLayouts.everyLayout().generator
        let mutable = try await checkMutableCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: layouts,
            options: LawCheckOptions(budget: .standard),
            laws: .ownOnly
        )
        let rangeReplaceable = try await checkRangeReplaceableCollectionPropertyLaws(
            for: Deque<Int>.self,
            using: layouts,
            options: LawCheckOptions(budget: .standard),
            laws: .ownOnly
        )
        #expect((mutable + rangeReplaceable).allSatisfy { $0.outcome == .passed })
    }
}
