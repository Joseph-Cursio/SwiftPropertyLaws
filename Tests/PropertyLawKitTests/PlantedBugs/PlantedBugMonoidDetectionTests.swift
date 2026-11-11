import PropertyBased
@testable import PropertyLawKit
import Testing

/// PRD §8 framework self-test gate — v1.8 kit-defined-algebraic cluster
/// (Monoid share). Plants violations against the two own Strict-tier
/// Monoid laws and asserts the framework's detection.
struct PlantedBugMonoidDetectionTests {

    @Test func detectsBadLeftIdentity() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkMonoidPropertyLaws(
                for: BadLeftIdentity.self,
                using: Gen<BadLeftIdentity>.badLeftIdentity(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Monoid.combineLeftIdentity"),
            "expected combineLeftIdentity in violation set; got: \(laws)"
        )
    }

    @Test func detectsBadRightIdentity() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkMonoidPropertyLaws(
                for: BadRightIdentity.self,
                using: Gen<BadRightIdentity>.badRightIdentity(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Monoid.combineRightIdentity"),
            "expected combineRightIdentity in violation set; got: \(laws)"
        )
    }
}
