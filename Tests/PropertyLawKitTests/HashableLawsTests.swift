import PropertyBased
@testable import PropertyLawKit
import Testing

struct HashableLawsTests {

    @Test func intsPassAllLaws() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) failed forInt")
        }
    }

    @Test func customStructPassesAllLaws() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Coordinate.self,
            using: Gen<Coordinate>.coordinate(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) failed forCoordinate")
        }
    }

    @Test func defaultLawSelectionRunsInheritedEquatableSuiteFirst() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstHashableIndex = laws.firstIndex { $0.hasPrefix("Hashable.") }
        #expect(firstHashableIndex != nil)
        let equatableLaws = laws[..<firstHashableIndex!]
        #expect(equatableLaws.allSatisfy { $0.hasPrefix("Equatable.") })
        #expect(equatableLaws.count == 4)
    }

    @Test func ownOnlySkipsInheritedEquatableSuite() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("Hashable.") })
        #expect(results.count == 3)
    }

    @Test func tiersAreReportedAsDocumented() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let tiersByLaw = Dictionary(uniqueKeysWithValues: results.map { ($0.protocolLaw, $0.tier) })
        #expect(tiersByLaw["Hashable.equalityConsistency"] == .strict)
        #expect(tiersByLaw["Hashable.stabilityWithinProcess"] == .conventional)
        #expect(tiersByLaw["Hashable.distribution"] == .heuristic)
    }
}
