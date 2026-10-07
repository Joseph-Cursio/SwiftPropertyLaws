import Testing
import PropertyBased
@testable import PropertyLawKit

struct StrideableLawsTests {

    @Test func intsPassAllLaws() async throws {
        let results = try await checkStrideablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            strideGenerator: Gen<Int>.int(in: -10...10),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Int")
        }
    }

    @Test func defaultLawSelectionRunsInheritedComparableSuiteFirst() async throws {
        let results = try await checkStrideablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            strideGenerator: Gen<Int>.int(in: -10...10),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstStrideableIndex = laws.firstIndex { $0.hasPrefix("Strideable.") }
        #expect(firstStrideableIndex != nil)
        let inheritedLaws = laws[..<firstStrideableIndex!]
        // Inherited block must contain Equatable's four + Comparable's five.
        #expect(inheritedLaws.contains { $0.hasPrefix("Equatable.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("Comparable.") })
        #expect(inheritedLaws.count == 9)
    }

    @Test func ownOnlySkipsInheritedSuites() async throws {
        let results = try await checkStrideablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            strideGenerator: Gen<Int>.int(in: -10...10),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("Strideable.") })
        #expect(results.count == 4)
    }

    @Test func tiersAreReportedAsDocumented() async throws {
        let results = try await checkStrideablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            strideGenerator: Gen<Int>.int(in: -10...10),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let tiersByLaw = Dictionary(uniqueKeysWithValues: results.map { ($0.protocolLaw, $0.tier) })
        #expect(tiersByLaw["Strideable.distanceRoundTrip"] == .strict)
        #expect(tiersByLaw["Strideable.advanceRoundTrip"] == .strict)
        #expect(tiersByLaw["Strideable.zeroAdvanceIdentity"] == .strict)
        #expect(tiersByLaw["Strideable.selfDistanceIsZero"] == .strict)
    }
}
