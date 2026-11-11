import PropertyBased
@testable import PropertyLawKit
import Testing

struct FixedWidthIntegerLawsTests {

    @Test func intsPassAllOwnLaws() async throws {
        let results = try await checkFixedWidthIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
        #expect(results.count == 9)
    }

    @Test func int32sPassAllLaws() async throws {
        let results = try await checkFixedWidthIntegerPropertyLaws(
            for: Int32.self,
            using: Gen<Int32>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int32")
        }
    }

    @Test func uintsPassAllLaws() async throws {
        let results = try await checkFixedWidthIntegerPropertyLaws(
            for: UInt.self,
            using: Gen<UInt>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for UInt")
        }
    }

    @Test func defaultRunsBinaryIntegerInheritedFirst() async throws {
        let results = try await checkFixedWidthIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstFixedWidthIndex = laws.firstIndex { $0.hasPrefix("FixedWidthInteger.") }
        #expect(firstFixedWidthIndex != nil)
        let inheritedLaws = laws[..<firstFixedWidthIndex!]
        #expect(inheritedLaws.contains { $0.hasPrefix("AdditiveArithmetic.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("Numeric.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("BinaryInteger.") })
        // 5 AdditiveArithmetic + 6 Numeric + 16 BinaryInteger = 27 inherited
        #expect(inheritedLaws.count == 27)
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkFixedWidthIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkFixedWidthIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "FixedWidthInteger.bitWidthMatchesType",
            "FixedWidthInteger.addingReportingOverflowConsistency",
            "FixedWidthInteger.subtractingReportingOverflowConsistency",
            "FixedWidthInteger.multipliedReportingOverflowConsistency",
            "FixedWidthInteger.dividedReportingOverflowOnDivByZero",
            "FixedWidthInteger.wrappingArithmeticDoesNotTrap",
            "FixedWidthInteger.minMaxBoundsAreReachable",
            "FixedWidthInteger.byteSwappedInvolution",
            "FixedWidthInteger.nonzeroBitCountRange",
        ])
    }
}
