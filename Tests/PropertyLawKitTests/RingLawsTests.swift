import PropertyBased
@testable import PropertyLawKit
import Testing

/// Test fixture: integers mod 5 — a finite commutative ring with unity.
/// Positive control across the whole Ring suite; values are bounded to
/// 0...4 so the three-sample associativity / distributivity laws stay cheap
/// and the arithmetic is exact.
struct IntMod5: Ring, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let zero = Self(value: 0)
    static let one = Self(value: 1)

    static func add(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: (lhs.value + rhs.value) % 5)
    }

    static func multiply(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: (lhs.value * rhs.value) % 5)
    }

    static func negate(_ value: Self) -> Self {
        Self(value: (5 - value.value) % 5)
    }

    var description: String { "IntMod5(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        Gen<Int>.int(in: 0...4).map { Self(value: $0) }
    }
}

/// Negative control — additive inverse is wrong (`negate(x) = x` instead of
/// `5 - x`). Everything else is a valid mod-5 ring, so only the two additive
/// inverse laws should fail.
struct BrokenInverseRing: Ring, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let zero = Self(value: 0)
    static let one = Self(value: 1)

    static func add(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: (lhs.value + rhs.value) % 5)
    }

    static func multiply(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: (lhs.value * rhs.value) % 5)
    }

    static func negate(_ value: Self) -> Self {
        // Wrong on purpose — should be `(5 - value.value) % 5`.
        Self(value: value.value)
    }

    var description: String { "BIR(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        // Skip 0 so every sample exposes the broken inverse (0 is its own
        // additive inverse, so x=0 wouldn't fail the law).
        Gen<Int>.int(in: 1...4).map { Self(value: $0) }
    }
}

/// Negative control — `multiply` is off by one (`(a*b + 1) % 5`), which
/// breaks both distributivity laws (and the multiply-identity laws, since
/// `multiply(x, .one) = x*1 + 1 = x + 1 ≠ x`). Used to confirm the
/// distributivity checks fire.
struct BrokenDistribRing: Ring, Equatable, Sendable, CustomStringConvertible {
    let value: Int

    static let zero = Self(value: 0)
    static let one = Self(value: 1)

    static func add(_ lhs: Self, _ rhs: Self) -> Self {
        Self(value: (lhs.value + rhs.value) % 5)
    }

    static func multiply(_ lhs: Self, _ rhs: Self) -> Self {
        // Wrong on purpose — the `+ 1` breaks distributivity.
        Self(value: (lhs.value * rhs.value + 1) % 5)
    }

    static func negate(_ value: Self) -> Self {
        Self(value: (5 - value.value) % 5)
    }

    var description: String { "BDR(\(value))" }

    static func gen() -> Generator<Self, some SendableSequenceType> {
        Gen<Int>.int(in: 0...4).map { Self(value: $0) }
    }
}

struct RingLawsTests {

    // Positive control — `IntMod5` (integers mod 5) is a finite commutative ring
    // with unity: addition and multiplication mod 5 satisfy all eleven laws.
    @Test func z5PassesAllElevenLaws() async throws {
        let results = try await checkRingPropertyLaws(
            for: IntMod5.self,
            using: IntMod5.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for IntMod5")
        }
        #expect(results.count == 11)
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkRingPropertyLaws(
            for: IntMod5.self,
            using: IntMod5.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPlan() async throws {
        let results = try await checkRingPropertyLaws(
            for: IntMod5.self,
            using: IntMod5.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "Ring.addAssociativity",
            "Ring.addCommutativity",
            "Ring.addLeftIdentity",
            "Ring.addRightIdentity",
            "Ring.addLeftInverse",
            "Ring.addRightInverse",
            "Ring.multiplyAssociativity",
            "Ring.multiplyLeftIdentity",
            "Ring.multiplyRightIdentity",
            "Ring.leftDistributivity",
            "Ring.rightDistributivity",
        ])
    }

    // Negative control — `BrokenInverseRing` returns `x` for `negate(x)`
    // (identity instead of additive inverse). Default enforcement throws.
    @Test func brokenAdditiveInverseThrows() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkRingPropertyLaws(
                for: BrokenInverseRing.self,
                using: BrokenInverseRing.gen(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    // Negative control — `BrokenInverseRing` fires *exactly* the two additive
    // inverse laws and nothing else (its add / multiply are otherwise a valid
    // mod-5 ring), proving the inverse laws are isolated.
    @Test func brokenAdditiveInverseFiresOnlyInverseLaws() async throws {
        do {
            _ = try await checkRingPropertyLaws(
                for: BrokenInverseRing.self,
                using: BrokenInverseRing.gen(),
                options: LawCheckOptions(budget: .standard)
            )
            Issue.record("expected a PropertyLawViolation")
        } catch let violation as PropertyLawViolation {
            let violated = Set(violation.results.filter(\.isViolation).map(\.protocolLaw))
            #expect(violated == [
                "Ring.addLeftInverse",
                "Ring.addRightInverse",
            ])
        }
    }

    // Negative control — `BrokenDistribRing` has a `multiply` that breaks
    // distributivity (off-by-one). Confirms the distributivity laws fire.
    @Test func brokenDistributivityFiresDistributivityLaws() async throws {
        do {
            _ = try await checkRingPropertyLaws(
                for: BrokenDistribRing.self,
                using: BrokenDistribRing.gen(),
                options: LawCheckOptions(budget: .standard)
            )
            Issue.record("expected a PropertyLawViolation")
        } catch let violation as PropertyLawViolation {
            let violated = Set(violation.results.filter(\.isViolation).map(\.protocolLaw))
            #expect(violated.contains("Ring.leftDistributivity"))
            #expect(violated.contains("Ring.rightDistributivity"))
        }
    }
}
