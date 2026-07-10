import OrderedCollections
import PropertyBased
import PropertyLawCollections
import PropertyLawKit
import Testing

/// M1 law runs for `OrderedDictionary<Int, Int>`. The dictionary itself is
/// Sequence-only (audit-confirmed not `Collection`), so collection-law
/// chains run against its views.
///
/// **Kit limitation surfaced by this slice:** `checkSequencePropertyLaws`
/// and the collection-chain checks require `Value.Element: Equatable`, and
/// dictionary-like carriers have tuple elements (`(key:, value:)`), which
/// cannot conform. That rules out the dictionary-as-Sequence run and the
/// `.elements` view here — and equally rules out stdlib `Dictionary` for
/// those entrypoints. Only `.values` (Element = Int) carries the chains.
/// Tracked as a Phase 2 candidate (element-equivalence adapter à la
/// `SameResult`) in the collections/async workplan.
struct OrderedDictionaryLawsTests {

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
