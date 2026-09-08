import Testing
@testable import PropertyLawKit

/// The walk itself: what it covers, where it stops, and what it reports.
struct EveryCaseLawsTests {

    /// Run a walk and hand back its result whether it passed or threw. A Strict
    /// violation throws under the default enforcement, and these tests are about
    /// what the result *says*, so the throw is unwrapped rather than avoided by
    /// weakening the tier.
    private func walk<Element: Sendable>(
        _ space: Enumeration<Element>,
        law: String,
        options: LawCheckOptions = LawCheckOptions(),
        satisfies property: @escaping @Sendable (Element) async throws -> Bool
    ) async -> CheckResult? {
        do {
            return try await checkEveryCase(of: space, law: law, options: options, satisfies: property).first
        } catch let violation as PropertyLawViolation {
            return violation.results.first
        } catch {
            return nil
        }
    }

    @Test func aPassingWalkReportsCompleteCoverage() async throws {
        let results = try await checkEveryCase(
            of: Every.subsets("subset", of: 6),
            law: "Spike.subsetsAreSorted",
            satisfies: { $0 == $0.sorted() }
        )
        let result = try #require(results.first)
        #expect(!result.isViolation)
        let coverage = try #require(result.coverage)
        #expect(coverage.casesRun == 64)
        #expect(coverage.spaceSize == 64)
        #expect(coverage.isComplete)
    }

    /// The property the whole design turns on. A space ordered smallest-first
    /// means the *first* failure found is the *smallest* failure that exists —
    /// not the smallest one a greedy descent happened to reach from a random
    /// starting point, which is what a shrinker gives.
    @Test func theFirstFailureFoundIsTheSmallestFailureThatExists() async {
        let result = await walk(
            Every.subsets("subset", of: 10),
            law: "Spike.cardinalityUnderThree",
            satisfies: { $0.count < 3 }
        )
        #expect(result?.isViolation == true)
        // The minimal witness of "cardinality >= 3" is the first three-element
        // subset, and no shrinking step was needed to say so.
        #expect(result?.counterexample == "subset=[0, 1, 2]")
        #expect(result?.shrinkSteps == 0)
        // 1 + 10 + 45 = 56 smaller cases were cleared first.
        #expect(result?.coverage?.casesRun == 57)
        #expect(result?.coverage?.spaceSize == 1024)
    }

    @Test func aWalkStopsAtTheFirstFailure() async {
        let counter = Counter()
        _ = await walk(
            Every.elements("value", in: 0 ..< 100),
            law: "Spike.underTen",
            satisfies: { value in counter.record(); return value < 10 }
        )
        #expect(counter.total == 11, "the walk should stop at the first failure, not finish the space")
    }

    @Test func aThrowingPropertyIsReportedWithItsAddress() async {
        struct Boom: Error {}
        let result = await walk(
            Every.elements("value", in: 0 ..< 5),
            law: "Spike.throwsAtThree",
            satisfies: { value in if value == 3 { throw Boom() }; return true }
        )
        let counterexample = result?.counterexample
        #expect(counterexample?.hasPrefix("value=3; threw") == true, "got \(counterexample ?? "nil")")
    }

    @Test func aTruncatedWalkReportsTheShortfallRatherThanClaimingCompleteness() async throws {
        let results = try await checkEveryCase(
            of: Every.subsets("subset", of: 10).prefix(100),
            law: "Spike.cardinalityUnderFive",
            satisfies: { $0.count < 5 }
        )
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.casesRun == 100)
        #expect(coverage.spaceSize == 1024)
        #expect(coverage.isComplete == false)
    }

    @Test func enforcementThrowsOnAStrictViolation() async {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkEveryCase(
                of: Every.elements("value", in: 0 ..< 3),
                law: "Spike.alwaysFails",
                satisfies: { _ in false }
            )
        }
    }

    @Test func aSkipSuppressionIsHonoured() async throws {
        let results = try await checkEveryCase(
            of: Every.elements("value", in: 0 ..< 3),
            law: "Spike.alwaysFails",
            options: LawCheckOptions(
                suppressions: [
                    LawSuppression(
                        identifier: LawIdentifier(protocolName: "Spike", lawName: "alwaysFails"),
                        kind: .skip,
                        reason: "spike"
                    )
                ]
            ),
            satisfies: { _ in false }
        )
        let result = try #require(results.first)
        #expect(!result.isViolation)
        if case .suppressed = result.outcome {} else { Issue.record("expected a suppressed outcome") }
    }

    // MARK: - The headline application: an algebraic law, walked rather than sampled

    /// `Semigroup.combineAssociativity` is a ternary law over one carrier. An
    /// 8-element carrier has 512 triples, which is a walk. Subtraction mod 8 is
    /// not associative, and the walk names the smallest triple that proves it.
    @Test func associativityOverEveryTripleOfASmallCarrier() async {
        let carrier = Every.elements("value", in: 0 ..< 8)
        let space = Every.triples(of: carrier)
        #expect(space.count == 512)

        let result = await walk(
            space,
            law: "Semigroup.combineAssociativity",
            satisfies: { triple in
                subtract(subtract(triple.first, triple.second), triple.third)
                    == subtract(triple.first, subtract(triple.second, triple.third))
            }
        )
        #expect(result?.isViolation == true)
        // (0 - 0) - 1 = 7, but 0 - (0 - 1) = 1. The second case in the walk.
        #expect(result?.counterexample == "value=0 / value=0 / value=1")
        #expect(result?.coverage?.casesRun == 2)
        #expect(result?.coverage?.spaceSize == 512)
    }

    /// The positive control for the same shape: addition mod 8 *is* associative,
    /// and the walk says so over all 512 triples rather than over a sample.
    @Test func anAssociativeOperationClearsEveryTriple() async throws {
        let space = Every.triples(of: Every.elements("value", in: 0 ..< 8))
        let results = try await checkEveryCase(
            of: space,
            law: "Semigroup.combineAssociativity",
            satisfies: { triple in
                ((triple.first + triple.second) % 8 + triple.third) % 8
                    == (triple.first + (triple.second + triple.third) % 8) % 8
            }
        )
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.isComplete)
        #expect(coverage.casesRun == 512)
    }
}

/// Subtraction mod 8 — associative-looking and not associative.
@Sendable private func subtract(_ lhs: Int, _ rhs: Int) -> Int { (lhs - rhs + 8) % 8 }

/// Counts property applications across the walk. The walk is sequential, so a
/// plain lock-free counter behind a class reference is enough.
private final class Counter: @unchecked Sendable {
    private var count = 0
    func record() { count += 1 }
    var total: Int { count }
}
