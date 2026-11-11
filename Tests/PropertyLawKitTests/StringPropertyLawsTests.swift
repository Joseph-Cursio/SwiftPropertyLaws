import PropertyBased
@testable import PropertyLawKit
import Testing

struct StringPropertyLawsTests {

    @Test func stringPassesAllOwnLaws() async throws {
        let results = try await checkStringProtocolPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for String")
        }
        #expect(results.count == 8)
    }

    @Test func substringPassesAllLaws() async throws {
        let results = try await checkStringProtocolPropertyLaws(
            for: Substring.self,
            using: TestGen.smallString().map { Substring($0) },
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(
                result.isViolation == false,
                "\(result.protocolLaw) should pass for Substring"
            )
        }
    }

    @Test func defaultRunsBidirectionalCollectionInheritedFirst() async throws {
        let results = try await checkStringProtocolPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = results.map(\.protocolLaw)
        let firstStringIndex = try #require(laws.firstIndex { $0.hasPrefix("StringProtocol.") })
        let inheritedLaws = laws[..<firstStringIndex]
        #expect(inheritedLaws.contains { $0.hasPrefix("BidirectionalCollection.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("Collection.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("Sequence.") })
        #expect(inheritedLaws.contains { $0.hasPrefix("IteratorProtocol.") })
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkStringProtocolPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkStringProtocolPropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "StringProtocol.stringInitRoundTrip",
            "StringProtocol.countMatchesStringInit",
            "StringProtocol.isEmptyMatchesCountZero",
            "StringProtocol.hasPrefixEmpty",
            "StringProtocol.hasSuffixEmpty",
            "StringProtocol.lowercasedIdempotent",
            "StringProtocol.uppercasedIdempotent",
            "StringProtocol.utf8ViewInvariance",
        ])
    }
}
