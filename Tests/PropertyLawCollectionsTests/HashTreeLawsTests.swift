import HashTreeCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

// MARK: - ValueSemantic probes
//
// Persistence is the CHAMP types' whole point: value copies share structure
// internally, so a node-sharing bug would leak a copy's mutation back into
// the original. The kit's ValueSemantic harness (copy-mutate-compare against
// a pristine twin) is exactly that check. `DefensiveCopy` does not apply —
// it is AnyObject-constrained, for reference types with copy()/clone().
//
// The probes wrap each type with a deterministic mutation surface rather
// than conforming the swift-collections types retroactively, keeping the
// conformance (and its Mutation enum) local to this test target.

private struct TreeSetProbe: ValueSemantic, Sendable {
    var storage: TreeSet<Int>

    enum Mutation: CaseIterable, Sendable {
        case insertNew
        case removeExisting
        case formUnion
        case formIntersection
        case formSymmetricDifference
    }

    static func makeProbe() -> TreeSetProbe {
        TreeSetProbe(storage: [1, 2, 3, 4, 5])
    }

    static func apply(_ mutation: Mutation, to target: inout TreeSetProbe) {
        switch mutation {
        case .insertNew: target.storage.insert(99)
        case .removeExisting: target.storage.remove(3)
        case .formUnion: target.storage.formUnion([7, 8, 9])
        case .formIntersection: target.storage.formIntersection([1, 2, 99])
        case .formSymmetricDifference: target.storage.formSymmetricDifference([2, 42])
        }
    }
}

private struct TreeDictionaryProbe: ValueSemantic, Sendable {
    var storage: TreeDictionary<Int, Int>

    enum Mutation: CaseIterable, Sendable {
        case insertNew
        case overwriteExisting
        case removeExisting
        case mergeOther
    }

    static func makeProbe() -> TreeDictionaryProbe {
        TreeDictionaryProbe(storage: [1: 10, 2: 20, 3: 30])
    }

    static func apply(_ mutation: Mutation, to target: inout TreeDictionaryProbe) {
        switch mutation {
        case .insertNew: target.storage[99] = 990
        case .overwriteExisting: target.storage[2] = -1
        case .removeExisting: target.storage[3] = nil
        case .mergeOther: target.storage.merge([4: 40, 1: -10]) { first, _ in first }
        }
    }
}

// MARK: - Law runs

/// M1 fifth slice: the CHAMP types. `TreeSet` carries SetAlgebra + the
/// Collection chain; `TreeDictionary` hits the same tuple-element limitation
/// as `OrderedDictionary` (its Sequence laws can't run), so its coverage is
/// Hashable/Codable plus the persistence probe.
struct HashTreeLawsTests {

    @Test func treeSetPassesSetAlgebraLaws() async throws {
        let results = try await checkSetAlgebraPropertyLaws(
            for: TreeSet<Int>.self,
            using: Gen<TreeSet<Int>>.smallIntTreeSet(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("SetAlgebra.symmetricDifferenceDefinition"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeSetPassesCollectionChain() async throws {
        let results = try await checkCollectionPropertyLaws(
            for: TreeSet<Int>.self,
            using: Gen<TreeSet<Int>>.smallIntTreeSet(),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.countConsistency"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeSetPassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: TreeSet<Int>.self,
            using: Gen<TreeSet<Int>>.smallIntTreeSet(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeSetPassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: TreeSet<Int>.self,
            using: Gen<TreeSet<Int>>.smallIntTreeSet(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeSetPersistenceHoldsUnderValueSemanticLaws() async throws {
        let results = try await checkValueSemanticPropertyLaws(
            for: TreeSetProbe.self,
            options: LawCheckOptions(budget: .standard)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeDictionaryPassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: TreeDictionary<Int, Int>.self,
            using: Gen<TreeDictionary<Int, Int>>.smallIntTreeDictionary(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeDictionaryPassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: TreeDictionary<Int, Int>.self,
            using: Gen<TreeDictionary<Int, Int>>.smallIntTreeDictionary(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func treeDictionaryPersistenceHoldsUnderValueSemanticLaws() async throws {
        let results = try await checkValueSemanticPropertyLaws(
            for: TreeDictionaryProbe.self,
            options: LawCheckOptions(budget: .standard)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
