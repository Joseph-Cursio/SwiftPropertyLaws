import Testing
import PropertyBased
@testable import PropertyLawKit

/// Phase 2 M3 payoff: dictionary-shaped carriers (tuple `Element`, which
/// cannot conform to `Equatable`) running the Sequence laws through the
/// `elementSameResult:` overload — including stdlib `Dictionary`, which no
/// kit entrypoint could accept before this adapter.
struct ElementEquivalenceSequenceLawsTests {

    private static func dictionaryGen() -> Generator<[Int: Int], some SendableSequenceType> {
        TestGen.smallInt().array(of: 0...8).map { keys in
            Dictionary(keys.map { ($0, $0 &* 3) }, uniquingKeysWith: { first, _ in first })
        }
    }

    @Test func dictionaryPassesSequenceLawsViaElementEquivalence() async throws {
        let results = try await checkSequencePropertyLaws(
            for: [Int: Int].self,
            using: Self.dictionaryGen(),
            elementSameResult: { $0.key == $1.key && $0.value == $1.value },
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        // The .all chain now includes the iterator laws — their Equatable
        // constraint was vestigial (they observe only nil/non-nil).
        #expect(names.contains("IteratorProtocol.terminationStability"))
        #expect(names.contains("Sequence.multiPassConsistency"))
        #expect(names.contains("Sequence.makeIteratorIndependence"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func equatableOverloadStillResolvesForArrays() async throws {
        // Guard against overload-resolution regressions: the original
        // Equatable entrypoint must keep winning for Equatable elements
        // when no elementSameResult is passed.
        let results = try await checkSequencePropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...6),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.isEmpty == false)
        #expect(results.allSatisfy { $0.outcome == .passed })
    }
}
