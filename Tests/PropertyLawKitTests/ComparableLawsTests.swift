import Testing
import PropertyBased
@testable import PropertyLawKit

struct ComparableLawsTests {

    @Test func intsPassAllLaws() async throws {
        let results = try await checkComparablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass forInt")
        }
    }

    @Test func stringsPassAllLaws() async throws {
        let results = try await checkComparablePropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass forString")
        }
    }

    @Test func defaultLawSelectionRunsInheritedEquatableSuiteFirst() async throws {
        let results = try await checkComparablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstComparableIndex = laws.firstIndex { $0.hasPrefix("Comparable.") }
        #expect(firstComparableIndex != nil)
        let inheritedLaws = laws[..<firstComparableIndex!]
        #expect(inheritedLaws.allSatisfy { $0.hasPrefix("Equatable.") })
        #expect(inheritedLaws.count == 4)
    }

    @Test func ownOnlySkipsInheritedEquatableSuite() async throws {
        let results = try await checkComparablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.protocolLaw.hasPrefix("Comparable.") })
        #expect(results.count == 5)
    }

    /// Irreflexivity is stated as `!(x < x)`, not as `x <= x`. The two agree for
    /// every type whose `<=` is derived from `<`, and disagree for NaN, whose `<=`
    /// is IEEE-754's and false — so the second spelling would fail every `Double`.
    @Test func irreflexivityHoldsForNaN() async throws {
        let results = try await checkComparablePropertyLaws(
            for: Double.self,
            using: Gen<Double>.doubleWithNaN(),
            options: LawCheckOptions(
                budget: .standard,
                suppressions: [.skip(.comparable(.totality), reason: "NaN is unordered")]
            ),
            laws: .ownOnly
        )
        let irreflexivity = try #require(results.first { $0.protocolLaw == "Comparable.irreflexivity" })
        #expect(irreflexivity.isViolation == false)
    }

    @Test func tiersAreReportedAsDocumented() async throws {
        let results = try await checkComparablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let tiersByLaw = Dictionary(uniqueKeysWithValues: results.map { ($0.protocolLaw, $0.tier) })
        #expect(tiersByLaw["Comparable.irreflexivity"] == .strict)
        #expect(tiersByLaw["Comparable.antisymmetry"] == .strict)
        #expect(tiersByLaw["Comparable.transitivity"] == .strict)
        #expect(tiersByLaw["Comparable.totality"] == .conventional)
        #expect(tiersByLaw["Comparable.operatorConsistency"] == .strict)
    }
}
