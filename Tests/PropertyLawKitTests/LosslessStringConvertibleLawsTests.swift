import PropertyBased
@testable import PropertyLawKit
import Testing

struct LosslessStringConvertibleLawsTests {

    @Test func intsPassRoundTrip() async throws {
        // Int conforms to LosslessStringConvertible — `Int("42") == 42`,
        // `Int("notanint") == nil`. The generator only produces valid ints,
        // so the round-trip always closes.
        let results = try await checkLosslessStringConvertiblePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
    }

    @Test func boolsPassRoundTrip() async throws {
        let results = try await checkLosslessStringConvertiblePropertyLaws(
            for: Bool.self,
            using: Gen<Bool>.bool,
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Bool")
        }
    }

    @Test func roundTripIsTheOnlyOwnLaw() async throws {
        let results = try await checkLosslessStringConvertiblePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results[0].protocolLaw == "LosslessStringConvertible.roundTrip")
        #expect(results[0].tier == .strict)
    }
}
