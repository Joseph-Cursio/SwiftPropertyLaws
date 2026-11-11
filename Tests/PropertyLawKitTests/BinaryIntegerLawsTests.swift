import PropertyBased
@testable import PropertyLawKit
import Testing

struct SignedIntegerLawsTests {

    @Test func intsPassAllLaws() async throws {
        let results = try await checkSignedIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
    }

    @Test func ownOnlyRunsOnlyTheOneOwnLaw() async throws {
        let results = try await checkSignedIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.count == 1)
        #expect(results[0].protocolLaw == "SignedInteger.signednessConsistency")
    }

    @Test func defaultRunsBinaryIntegerAndSignedNumericFirst() async throws {
        let results = try await checkSignedIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        #expect(laws.contains { $0.hasPrefix("BinaryInteger.") })
        #expect(laws.contains { $0.hasPrefix("SignedNumeric.") })
        #expect(laws.contains { $0.hasPrefix("Numeric.") })
        #expect(laws.contains { $0.hasPrefix("AdditiveArithmetic.") })
        // SignedNumeric is run with .ownOnly to avoid double-running Numeric;
        // assert exactly one Numeric.* block exists.
        let numericCount = laws.filter { $0.hasPrefix("Numeric.") }.count
        #expect(numericCount == 6)
    }
}

struct UnsignedIntegerLawsTests {

    @Test func uintsPassAllLaws() async throws {
        let results = try await checkUnsignedIntegerPropertyLaws(
            for: UInt.self,
            using: Gen<UInt>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for UInt")
        }
    }

    @Test func ownOnlyRunsOnlyTheTwoOwnLaws() async throws {
        let results = try await checkUnsignedIntegerPropertyLaws(
            for: UInt.self,
            using: Gen<UInt>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "UnsignedInteger.nonNegative",
            "UnsignedInteger.magnitudeIsSelf",
        ])
    }
}

struct BinaryIntegerLawsTests {

    @Test func intsPassAllOwnLaws() async throws {
        let results = try await checkBinaryIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
        #expect(results.count == 16)
    }

    @Test func uintsPassAllOwnLaws() async throws {
        let results = try await checkBinaryIntegerPropertyLaws(
            for: UInt.self,
            using: Gen<UInt>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for UInt")
        }
    }

    @Test func defaultLawSelectionRunsInheritedNumericFirst() async throws {
        let results = try await checkBinaryIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstBinaryIntegerIndex = try #require(laws.firstIndex { $0.hasPrefix("BinaryInteger.") })
        let inheritedLaws = laws[..<firstBinaryIntegerIndex]
        #expect(inheritedLaws.contains { $0.hasPrefix("AdditiveArithmetic.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("Numeric.") })
        // 5 AdditiveArithmetic + 6 Numeric = 11 inherited
        #expect(inheritedLaws.count == 11)
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkBinaryIntegerPropertyLaws(
            for: Int.self,
            using: Gen<Int>.boundedForArithmetic(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }
}
