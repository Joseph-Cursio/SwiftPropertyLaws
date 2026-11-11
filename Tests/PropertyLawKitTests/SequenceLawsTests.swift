import PropertyBased
@testable import PropertyLawKit
import Testing

struct SequenceLawsTests {

    @Test func arrayPassesAllLawsIncludingInheritedIterator() async throws {
        let results = try await checkSequencePropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard),
            laws: .all
        )
        let names = results.map(\.protocolLaw)
        // Inherited IteratorProtocol suite ran first.
        #expect(names.contains("IteratorProtocol.terminationStability"))
        #expect(names.contains("IteratorProtocol.singlePassYield"))
        // Sequence's own suite.
        #expect(names.contains("Sequence.underestimatedCountLowerBound"))
        #expect(names.contains("Sequence.multiPassConsistency"))
        #expect(names.contains("Sequence.makeIteratorIndependence"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func ownOnlySkipsInheritedIteratorSuite() async throws {
        let results = try await checkSequencePropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains { $0.hasPrefix("IteratorProtocol.") } == false)
        #expect(names.allSatisfy { $0.hasPrefix("Sequence.") })
    }

    @Test func singlePassSuppressesMultiPassAndIndependenceChecks() async throws {
        let results = try await checkSequencePropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...4),
            options: LawCheckOptions(budget: .sanity),
            sequenceOptions: SequenceLawOptions(passing: .singlePass),
            laws: .ownOnly
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Sequence.underestimatedCountLowerBound"))
        #expect(names.contains("Sequence.multiPassConsistency") == false)
        #expect(names.contains("Sequence.makeIteratorIndependence") == false)
    }

    @Test func detectsLyingUnderestimatedCount() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSequencePropertyLaws(
                for: LyingUnderestimatedCount.self,
                using: Gen<LyingUnderestimatedCount>.lyingUnderestimated(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Sequence.underestimatedCountLowerBound"),
            "expected underestimatedCountLowerBound; got: \(laws)"
        )
    }

    @Test func detectsSharedCounterPerturbation() async throws {
        // SharedCounterSequence violates multiPassConsistency / independence.
        // Both are Conventional, so default enforcement reports without
        // throwing — escalate to .strict to assert the violation surfaces.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSequencePropertyLaws(
                for: SharedCounterSequence.self,
                using: Gen<SharedCounterSequence>.sharedCounter(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Sequence.multiPassConsistency")
                || laws.contains("Sequence.makeIteratorIndependence"),
            "expected multi-pass / independence violation; got: \(laws)"
        )
    }
}
