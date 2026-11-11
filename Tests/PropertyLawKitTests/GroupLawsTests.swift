import PropertyBased
@testable import PropertyLawKit
import Testing

/// Test fixture: `Int`-wrapping `Group` whose `combine` is addition,
/// `identity` is 0, and `inverse(x)` is `-x`. Positive control across
/// the Group suite — the canonical additive group of integers.
struct AdditiveInt: Group, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = Self(value: 0)

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: lhs.value &+ rhs.value)
    }

    static func inverse(_ value: Self) -> Self {
        Self(value: 0 &- value.value)
    }

    var description: String { "AInt(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        // Bounded range avoids the &+ wraparound from masking inverse-law
        // failures on overflow; ±100 keeps the per-trial arithmetic exact.
        Gen<Int>.int(in: -100...100).map { Self(value: $0) }
    }
}

/// Negative control — `inverse(x) = x` is wrong (the identity function
/// is only an inverse when x is itself the identity). Used in the
/// `brokenInverseFailsBothInverseLaws` test to confirm the
/// Group inverse laws fire the Strict violation they should.
struct BrokenInverse: Group, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = Self(value: 0)

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: lhs.value &+ rhs.value)
    }

    static func inverse(_ value: Self) -> Self {
        // Wrong on purpose — should be `-value.value`, not `value.value`.
        Self(value: value.value)
    }

    var description: String { "BI(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        // Generator skips 0 so every sample exposes the broken-inverse bug
        // (0's inverse IS 0, so x=0 wouldn't fail the law).
        Gen<Int>.int(in: 1...100).map { Self(value: $0) }
    }
}

struct GroupLawsTests {

    // Positive control — `AdditiveInt` (`(Int, +, 0, -)`) is the canonical
    // additive group: addition is associative, 0 is two-sided identity,
    // negation is two-sided inverse.
    @Test func additiveIntPassesAllFiveLaws() async throws {
        let results = try await checkGroupPropertyLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for AdditiveInt")
        }
        // 1 inherited Semigroup + 2 inherited Monoid + 2 own Group = 5.
        #expect(results.count == 5)
    }

    @Test func ownOnlySkipsInheritedLaws() async throws {
        let results = try await checkGroupPropertyLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.count == 2)
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Group.combineLeftInverse",
            "Group.combineRightInverse",
        ])
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkGroupPropertyLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkGroupPropertyLaws(
            for: AdditiveInt.self,
            using: AdditiveInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Semigroup.combineAssociativity",
            "Monoid.combineLeftIdentity",
            "Monoid.combineRightIdentity",
            "Group.combineLeftInverse",
            "Group.combineRightInverse",
        ])
    }

    // Negative control — `BrokenInverse` returns `x` for `inverse(x)`
    // (identity instead of inverse). The own-only check surfaces both
    // inverse violations; `.default` enforcement throws.
    @Test func brokenInverseFailsBothInverseLaws() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkGroupPropertyLaws(
                for: BrokenInverse.self,
                using: BrokenInverse.gen(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
    }
}
