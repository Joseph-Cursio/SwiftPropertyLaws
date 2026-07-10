import OrderedCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// M1 law runs for `OrderedDictionary<Int, Int>`. The dictionary itself is
/// Sequence-only (audit-confirmed not `Collection`), so collection-law
/// chains run against its views.
///
/// **Kit limitation (closed across Phase 2 M3–M4):** dictionary-like
/// carriers have tuple elements (`(key:, value:)`), which cannot conform to
/// `Equatable`. The Sequence and Collection laws now run through the kit's
/// `elementSameResult:` overloads — including the `.elements` view that M1
/// had to skip. (`Bidirectional`/`RandomAccess` index laws still require
/// the Equatable entrypoints; `.values` with Element = Int carries those.)
struct OrderedDictionaryLawsTests {

    @Test func elementsViewPassesCollectionLawsViaElementEquivalence() async throws {
        let results = try await checkCollectionPropertyLaws(
            for: OrderedDictionary<Int, Int>.Elements.self,
            using: Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary()
                .map { dictionary in dictionary.elements },
            elementSameResult: { $0.key == $1.key && $0.value == $1.value },
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Collection.indexValidity"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func orderedDictionaryPassesSequenceLawsViaElementEquivalence() async throws {
        let results = try await checkSequencePropertyLaws(
            for: OrderedDictionary<Int, Int>.self,
            using: Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary(),
            elementSameResult: { $0.key == $1.key && $0.value == $1.value },
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Sequence.multiPassConsistency"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func valuesViewPassesRandomAccessAndMutableLaws() async throws {
        let randomAccessResults = try await checkRandomAccessCollectionPropertyLaws(
            for: OrderedDictionary<Int, Int>.Values.self,
            using: Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary()
                .map { dictionary in dictionary.values },
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        let mutableResults = try await checkMutableCollectionPropertyLaws(
            for: OrderedDictionary<Int, Int>.Values.self,
            using: Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary()
                .map { dictionary in dictionary.values },
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(randomAccessResults.allSatisfy { $0.outcome == .passed })
        #expect(mutableResults.isEmpty == false)
        #expect(mutableResults.allSatisfy { $0.outcome == .passed })
    }

    @Test func orderedDictionaryPassesHashableLawsIncludingEquatable() async throws {
        let results = try await checkHashablePropertyLaws(
            for: OrderedDictionary<Int, Int>.self,
            using: Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary(),
            options: LawCheckOptions(budget: .sanity),
            laws: .all
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func orderedDictionaryPassesCodableRoundTrip() async throws {
        let results = try await checkCodablePropertyLaws(
            for: OrderedDictionary<Int, Int>.self,
            using: Gen<OrderedDictionary<Int, Int>>.smallIntOrderedDictionary(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
