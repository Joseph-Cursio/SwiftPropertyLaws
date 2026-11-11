@testable import PropertyLawKit
import Testing

struct MonoidLawsTests {

    // Positive control — `StringMonoid` is the canonical free monoid;
    // empty string is identity, concat is associative.
    @Test func stringMonoidPassesAllThreeLaws() async throws {
        let results = try await checkMonoidPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for StringMonoid")
        }
        // 1 inherited Semigroup law + 2 own Monoid laws = 3.
        #expect(results.count == 3)
    }

    @Test func ownOnlySkipsInheritedSemigroupLaw() async throws {
        let results = try await checkMonoidPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.count == 2)
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Monoid.combineLeftIdentity",
            "Monoid.combineRightIdentity",
        ])
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkMonoidPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkMonoidPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Semigroup.combineAssociativity",
            "Monoid.combineLeftIdentity",
            "Monoid.combineRightIdentity",
        ])
    }
}
