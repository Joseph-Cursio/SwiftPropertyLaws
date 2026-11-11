import PropertyBased
@testable import PropertyLawKit
import Testing

/// Test fixture: `Int`-wrapping `Semilattice` whose `combine` is `max`
/// and `identity` is `Int.min`. Positive control across the Semilattice
/// suite — the canonical bounded join-semilattice of integers.
struct MaxInt: Semilattice, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = Self(value: .min)

    static func combine(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: max(lhs.value, rhs.value))
    }

    var description: String { "Max(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        Gen<Int>.int(in: -100...100).map { Self(value: $0) }
    }
}

/// Negative control — integer addition is associative + commutative + has
/// identity but is NOT idempotent (`1 + 1 = 2 ≠ 1`). Used in the
/// `tallyFailsIdempotence` test to confirm the Semilattice idempotence
/// law fires the Strict violation it should. Generator skips 0 so every
/// sample exposes the bug (0 + 0 = 0 wouldn't fail).
struct NonIdempotentTally: Semilattice, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let identity = Self(value: 0)

    static func combine(
        _ lhs: Self,
        _ rhs: Self
    ) -> Self {
        Self(value: lhs.value &+ rhs.value)
    }

    var description: String { "NIT(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        Gen<Int>.int(in: 1...100).map { Self(value: $0) }
    }
}

struct SemilatticeLawsTests {

    // Positive control — `MaxInt` (`(Int, max, .min)`) is the canonical
    // bounded join-semilattice over integers: max is associative,
    // commutative, idempotent, and Int.min is the two-sided identity.
    @Test func maxIntPassesAllFiveLaws() async throws {
        let results = try await checkSemilatticePropertyLaws(
            for: MaxInt.self,
            using: MaxInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for MaxInt")
        }
        // 1 inherited Semigroup + 2 inherited Monoid + 1 inherited
        // CommutativeMonoid + 1 own Semilattice = 5.
        #expect(results.count == 5)
    }

    @Test func ownOnlySkipsInheritedLaws() async throws {
        let results = try await checkSemilatticePropertyLaws(
            for: MaxInt.self,
            using: MaxInt.gen(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        #expect(results.count == 1)
        let names = Set(results.map(\.protocolLaw))
        #expect(names == ["Semilattice.combineIdempotence"])
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkSemilatticePropertyLaws(
            for: MaxInt.self,
            using: MaxInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkSemilatticePropertyLaws(
            for: MaxInt.self,
            using: MaxInt.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Semigroup.combineAssociativity",
            "Monoid.combineLeftIdentity",
            "Monoid.combineRightIdentity",
            "CommutativeMonoid.combineCommutativity",
            "Semilattice.combineIdempotence",
        ])
    }

    // Negative control — `Tally` (integer addition) is a CommutativeMonoid
    // but NOT a Semilattice: addition is not idempotent (1+1 ≠ 1). The
    // own-only check surfaces the violation; `.default` enforcement throws.
    @Test func tallyFailsIdempotence() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkSemilatticePropertyLaws(
                for: NonIdempotentTally.self,
                using: NonIdempotentTally.gen(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
    }
}
