import AsyncAlgorithms
import PropertyBased
import PropertyLawAsync
import PropertyLawKit
import Testing

struct AsyncSequenceLawsTests {

    private static func smallIntArrays() -> Generator<[Int], some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: 0 ... 8)
    }

    @Test func intArraysPassAllAsyncSequenceLaws() async throws {
        let results = try await checkAsyncSequencePropertyLaws(
            for: [Int].self,
            using: Self.smallIntArrays(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        for law in AsyncSequenceLaw.allCases {
            #expect(
                names.contains("AsyncSequence.\(law.rawValue)"),
                "missing law \(law.rawValue)"
            )
        }
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    /// The order-insensitivity of the merge law, witnessed concretely:
    /// multisets agree even though interleavings may differ run to run.
    @Test func mergeMultisetWitness() async throws {
        let left = [1, 2, 3]
        let right = [10, 20]
        var merged: [Int] = []
        for await element in merge(left.async, right.async) {
            merged.append(element)
        }
        #expect(merged.sorted() == [1, 2, 3, 10, 20])
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.asyncSequence(.mergePreservesElementMultiset)
        #expect(identifier.qualifiedName == "AsyncSequence.mergePreservesElementMultiset")
    }
}
