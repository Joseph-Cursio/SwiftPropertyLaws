import Testing
import PropertyBased
@testable import PropertyLawKit

struct BinaryFloatingPointLawsTests {

    @Test func doublesPassAllOwnLaws() async throws {
        let results = try await checkBinaryFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Double")
        }
        #expect(results.count == 4)
    }

    @Test func floatsPassAllLaws() async throws {
        let results = try await checkBinaryFloatingPointPropertyLaws(
            for: Float.self,
            using: Gen<Float>.float(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Float")
        }
    }

    @Test func defaultRunsInheritedFloatingPointFirst() async throws {
        let results = try await checkBinaryFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstBinaryFPIndex = laws.firstIndex { $0.hasPrefix("BinaryFloatingPoint.") }
        #expect(firstBinaryFPIndex != nil)
        let inheritedLaws = laws[..<firstBinaryFPIndex!]
        #expect(inheritedLaws.allSatisfy { $0.hasPrefix("FloatingPoint.") })
        // 11 always-on FloatingPoint laws (allowNaN: false by default)
        #expect(inheritedLaws.count == 11)
    }

    @Test func allowNaNPropagatesToInheritedFloatingPointSuite() async throws {
        let results = try await checkBinaryFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity, allowNaN: true)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names.contains("FloatingPoint.nanIsNaN"))
        #expect(names.contains("FloatingPoint.nanInequality"))
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkBinaryFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkBinaryFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "BinaryFloatingPoint.radix2Constraint",
            "BinaryFloatingPoint.significandExponentReconstruction",
            "BinaryFloatingPoint.binadeMembership",
            "BinaryFloatingPoint.convertingFromIntegerExactness"
        ])
    }
}
