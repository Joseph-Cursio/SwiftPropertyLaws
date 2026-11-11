import PropertyBased
@testable import PropertyLawKit
import Testing

/// PRD §8 framework self-test gate — v1.8 kit-defined-algebraic cluster.
/// Plants a violation against `Semigroup.combineAssociativity` and asserts
/// the framework's detection.
struct PlantedBugSemigroupDetectionTests {

    @Test func detectsNonAssociativeCombine() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSemigroupPropertyLaws(
                for: NonAssociativeCombine.self,
                using: Gen<NonAssociativeCombine>.nonAssociativeCombine(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Semigroup.combineAssociativity"),
            "expected combineAssociativity in violation set; got: \(laws)"
        )
    }
}
