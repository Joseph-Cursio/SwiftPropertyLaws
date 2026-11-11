import PropertyBased
@testable import PropertyLawKit
import Testing

struct SignedNumericLawsTests {

    @Test func intsPassAllLawsAtBoundedRange() async throws {
        let results = try await checkSignedNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
    }

    @Test func defaultLawSelectionRunsInheritedSuitesFirst() async throws {
        let results = try await checkSignedNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstSignedNumericIndex = laws.firstIndex { $0.hasPrefix("SignedNumeric.") }
        #expect(firstSignedNumericIndex != nil)
        let inheritedLaws = laws[..<firstSignedNumericIndex!]
        #expect(inheritedLaws.contains { $0.hasPrefix("AdditiveArithmetic.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("Numeric.") })
        // 5 AdditiveArithmetic + 6 Numeric = 11 inherited
        #expect(inheritedLaws.count == 11)
    }

    @Test func ownOnlySkipsInheritedSuite() async throws {
        let results = try await checkSignedNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("SignedNumeric.") })
        #expect(results.count == 4)
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkSignedNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkSignedNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "SignedNumeric.negationInvolution",
            "SignedNumeric.additiveInverse",
            "SignedNumeric.negationDistributesOverAddition",
            "SignedNumeric.negateMutationConsistency",
        ])
    }
}
