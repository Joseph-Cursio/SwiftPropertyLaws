import PropertyBased
@testable import PropertyLawKit
import Testing

/// Test fixture: `String`-wrapping `Monoid` whose `combine` is the
/// canonical concatenation and `identity` is the empty string. Used as a
/// positive control across both Semigroup and Monoid suites — the
/// canonical free monoid over the alphabet of Swift `Character`s.
struct StringMonoid: Monoid, Equatable, Sendable, CustomStringConvertible {
    let value: String

    static let identity = Self(value: "")

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: lhs.value + rhs.value)
    }

    var description: String { "SM(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        Gen<Character>.letterOrNumber.string(of: 0...4).map { Self(value: $0) }
    }
}

struct SemigroupLawsTests {

    // Positive control — `String` under concatenation is the canonical
    // free semigroup. Concat is associative for any string inputs.
    @Test func stringConcatenationPassesAssociativity() async throws {
        let results = try await checkSemigroupPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for StringMonoid")
        }
        #expect(results.count == 1)
    }

    @Test func tierIsReportedAsStrict() async throws {
        let results = try await checkSemigroupPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNameMatchesPRD() async throws {
        let results = try await checkSemigroupPropertyLaws(
            for: StringMonoid.self,
            using: StringMonoid.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == ["Semigroup.combineAssociativity"])
    }
}
