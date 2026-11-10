import PropertyBased
@testable import PropertyLawKit
import Testing

struct AdditiveArithmeticLawsTests {

    @Test func intsPassAllFiveLaws() async throws {
        let results = try await checkAdditiveArithmeticPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
        #expect(results.count == 5)
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkAdditiveArithmeticPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkAdditiveArithmeticPropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "AdditiveArithmetic.additionAssociativity",
            "AdditiveArithmetic.additionCommutativity",
            "AdditiveArithmetic.zeroAdditiveIdentity",
            "AdditiveArithmetic.subtractionInverse",
            "AdditiveArithmetic.selfSubtractionIsZero",
        ])
    }
}
