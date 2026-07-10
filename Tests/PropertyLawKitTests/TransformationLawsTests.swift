import Testing
import PropertyBased
@testable import PropertyLawKit

struct TransformationLawsTests {

    @Test func arrayOfIntPassesAllTransformationLaws() async throws {
        let results = try await checkTransformationPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        // The closure-free half only — the parameterized four (mapFusion
        // etc.) require a `functions:` argument and are covered in
        // TransformationFunctionLawsTests.
        let closureFree: [TransformationLaw] = [
            .sortedIdempotence, .sortedIsNonDecreasing,
            .sortedPreservesCount, .reversedInvolution
        ]
        for law in closureFree {
            #expect(
                names.contains("Transformation.\(law.rawValue)"),
                "missing law \(law.rawValue)"
            )
        }
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func stringPassesAllTransformationLaws() async throws {
        // String is a Sequence of Comparable Characters — the transformation
        // laws see it as a character sequence (sorted() yields [Character]).
        let results = try await checkTransformationPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func lawIdentifierFactoryMatchesEmittedNames() {
        let identifier = LawIdentifier.transformation(.sortedIdempotence)
        #expect(identifier.qualifiedName == "Transformation.sortedIdempotence")
    }
}
