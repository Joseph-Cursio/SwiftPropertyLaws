@testable import PropertyLawKit
import Testing

struct NumericLawsTests {

    @Test func intsPassAllLawsAtBoundedRange() async throws {
        let results = try await checkNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
    }

    @Test func defaultLawSelectionRunsInheritedAdditiveArithmeticFirst() async throws {
        let results = try await checkNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstNumericIndex = try #require(laws.firstIndex { $0.hasPrefix("Numeric.") })
        let inheritedLaws = laws[..<firstNumericIndex]
        #expect(inheritedLaws.allSatisfy { $0.hasPrefix("AdditiveArithmetic.") })
        #expect(inheritedLaws.count == 5)
    }

    @Test func ownOnlySkipsInheritedSuite() async throws {
        let results = try await checkNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("Numeric.") })
        #expect(results.count == 6)
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkNumericPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Numeric.multiplicationAssociativity",
            "Numeric.multiplicationCommutativity",
            "Numeric.oneMultiplicativeIdentity",
            "Numeric.zeroAnnihilation",
            "Numeric.leftDistributivity",
            "Numeric.rightDistributivity",
        ])
    }
}
