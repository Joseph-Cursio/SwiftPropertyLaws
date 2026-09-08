import PropertyBased
import Testing
@testable import PropertyLawKit

/// Each law is verified by a comparator that violates it and nothing else, so a
/// pass is evidence the law discriminates rather than evidence the suite is green.
@Suite("Strict weak ordering — laws over a supplied comparator")
struct StrictWeakOrderingLawsTests {

    private struct Decl: Equatable, Sendable, CustomStringConvertible {
        var line: Int
        var column: Int
        var description: String { "\(line):\(column)" }
    }

    private func decls() -> Generator<Decl, some SendableSequenceType> {
        zip(Gen<Int>.int(in: 0...4), Gen<Int>.int(in: 0...4))
            .map { Decl(line: $0, column: $1) }
    }

    private let sanity = LawCheckOptions(budget: .sanity)

    /// Conventional-tier laws report rather than throw — a narrow generator that
    /// cannot demonstrate the property is outside the caller's control, so the
    /// suite hands back the outcome and `.strict` promotes it. So these two are
    /// asserted on the returned results, not on a thrown violation.
    private func failed(_ results: [CheckResult], _ law: String) -> Bool {
        results.contains {
            guard $0.protocolLaw == law else { return false }
            if case .failed = $0.outcome { return true }
            return false
        }
    }

    // MARK: - The correct comparator satisfies everything

    @Test("a lexicographic (line, column) order satisfies all six laws")
    func correctComparatorPasses() async throws {
        let byLineThenColumn: @Sendable (Decl, Decl) -> Bool = {
            $0.line != $1.line ? $0.line < $1.line : $0.column < $1.column
        }
        try await checkStrictWeakOrderingLaws(over: decls(), by: byLineThenColumn, options: sanity)
        try await checkComparatorDiscriminates(
            over: decls(), by: byLineThenColumn, distinct: { $0 != $1 }, options: sanity)
        try await checkComparatorIsCongruent(over: decls(), by: byLineThenColumn, options: sanity)
    }

    // MARK: - One violator per law

    @Test("irreflexivity catches `<=` written where `<` was meant")
    func nonStrictComparatorFails() async {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkStrictWeakOrderingLaws(
                over: decls(), by: { $0.line <= $1.line }, options: sanity)
        }
    }

    @Test("transitivity catches a comparator that is not an order at all")
    func intransitiveComparatorFails() async {
        // Orders by line modulo 3 — a cycle, so a < b < c < a.
        await #expect(throws: PropertyLawViolation.self) {
            try await checkStrictWeakOrderingLaws(
                over: decls(),
                by: { ($0.line + 1) % 3 == $1.line % 3 },
                options: sanity)
        }
    }

    @Test("incomparability transitivity catches equivalence that is not one")
    func nonTransitiveEquivalenceFails() async {
        // "Within 1 of each other" is reflexive and symmetric and not transitive:
        // 0 ~ 1 and 1 ~ 2, but 0 is ordered against 2.
        await #expect(throws: PropertyLawViolation.self) {
            try await checkStrictWeakOrderingLaws(
                over: decls(),
                by: { $1.line - $0.line > 1 },
                options: sanity)
        }
    }

    // MARK: - The historical defect, and which law actually catches it

    /// **The point of splitting discrimination out.** SwiftInferProperties had
    /// five comparators that stopped at `line` and ignored `column`, so two
    /// declarations sharing a line compared equivalent and their order fell to a
    /// sort Swift does not promise is stable.
    ///
    /// That comparator is a *valid* strict weak ordering — its equivalence
    /// classes are simply larger than intended. The four laws pass it. Only
    /// discrimination fails it, which is why it is a separate entry point and
    /// not folded into the suite.
    @Test("the line-only comparator passes the four laws and fails discrimination")
    func lossyKeyIsAValidOrderingAndDoesNotDiscriminate() async throws {
        let byLineOnly: @Sendable (Decl, Decl) -> Bool = { $0.line < $1.line }

        // Passes — this is a legitimate strict weak ordering.
        try await checkStrictWeakOrderingLaws(over: decls(), by: byLineOnly, options: sanity)

        // Reports — distinct declarations on one line are unordered. A Conventional
        // violation surfaces as a recorded issue rather than a throw, and
        // `withKnownIssue` fails if nothing is recorded, so this block IS the assertion.
        var results: [CheckResult] = []
        await withKnownIssue("discrimination fails at Conventional tier, by design") {
            results = try await checkComparatorDiscriminates(
                over: decls(), by: byLineOnly, distinct: { $0 != $1 }, options: sanity)
        }
        #expect(failed(results, "StrictWeakOrdering.discrimination"),
                "the line-only comparator must fail discrimination")
    }

    /// The other half of that: a comparator with deliberate equivalence classes
    /// must not be reported by the suite, which is why discrimination is opt-in.
    @Test("deliberate equivalence classes are not a suite failure")
    func groupingComparatorIsNotReportedBySuite() async throws {
        try await checkStrictWeakOrderingLaws(
            over: decls(), by: { $0.line < $1.line }, options: sanity)
    }

    // MARK: - Congruence

    /// A comparator reading something `==` does not see.
    ///
    /// `Tagged`'s equality is its `key`; `tag` is invisible to `==`. A comparator
    /// keyed on `tag` therefore orders two equal values differently against the
    /// same probe. That is the copy-on-write hazard in deterministic form —
    /// storage identity is the usual way a comparator reaches a field equality
    /// does not see, but any such field will do, and an identity-based violator
    /// would make this test depend on heap address ordering.
    @Test("congruence catches a comparator reading a field `==` ignores")
    func comparatorReadingInvisibleFieldFails() async throws {
        struct Tagged: Equatable, Sendable, CustomStringConvertible {
            let key: Int
            let tag: Int
            static func == (lhs: Tagged, rhs: Tagged) -> Bool { lhs.key == rhs.key }
            var description: String { "Tagged(key: \(key), tag: \(tag))" }
        }
        let generator = zip(Gen<Int>.int(in: 0...2), Gen<Int>.int(in: 0...3))
            .map { Tagged(key: $0, tag: $1) }

        var results: [CheckResult] = []
        await withKnownIssue("congruence fails at Conventional tier, by design") {
            results = try await checkComparatorIsCongruent(
                over: generator, by: { $0.tag < $1.tag }, options: sanity)
        }
        #expect(failed(results, "StrictWeakOrdering.congruence"),
                "a comparator reading a field `==` ignores must fail congruence")
    }


    // MARK: - The vacuity guard

    /// **A conditional law whose antecedent never fires passes having tested
    /// nothing**, and that is the failure mode random sampling hides. Congruence
    /// needs two equal values; over a domain wide enough that collisions never
    /// happen it goes green for free — on exactly the callers most likely to
    /// need it.
    ///
    /// A single-value domain is the cheapest way to force the opposite case, so
    /// this test uses a generator that cannot produce a *distinct* pair and
    /// checks that discrimination reports rather than passes.
    @Test("discrimination reports vacuity when no two values are distinct")
    func discriminationOnConstantGeneratorIsVacuous() async throws {
        let constant = Gen<Int>.int(in: 7...7).map { Decl(line: $0, column: 0) }
        var results: [CheckResult] = []
        await withKnownIssue("vacuity is reported at Conventional tier") {
            results = try await checkComparatorDiscriminates(
                over: constant,
                by: { $0.line < $1.line },
                distinct: { $0 != $1 },
                options: sanity)
        }
        #expect(failed(results, "StrictWeakOrdering.discrimination"),
                "a generator that cannot produce two distinct values must not pass")
        let text = results.first.map { String(describing: $0.outcome) } ?? ""
        #expect(text.contains("vacuous"), "the failure must say why: \(text)")
    }

    /// The control. The same law over a generator that *can* produce distinct
    /// values passes — so the guard is reporting emptiness, not reporting always.
    @Test("discrimination passes on a generator that does produce distinct values")
    func discriminationOnWideGeneratorPasses() async throws {
        let byLineThenColumn: @Sendable (Decl, Decl) -> Bool = {
            $0.line != $1.line ? $0.line < $1.line : $0.column < $1.column
        }
        try await checkComparatorDiscriminates(
            over: decls(), by: byLineThenColumn, distinct: { $0 != $1 }, options: sanity)
    }

    /// Congruence over a generator whose values are all distinct never sees an
    /// equal pair, so it has nothing to check and must say so.
    @Test("congruence reports vacuity when no two values are equal")
    func congruenceWithoutEqualPairsIsVacuous() async throws {
        // A domain wide enough that two draws colliding is vanishingly unlikely,
        // which is the realistic case: `congruence` needs an equal pair, and over
        // any ordinary value type the generator will not produce one.
        let allDistinct = Gen<Int>.int(in: 0...1_000_000).map { Decl(line: 0, column: $0) }
        var results: [CheckResult] = []
        await withKnownIssue("vacuity is reported at Conventional tier") {
            results = try await checkComparatorIsCongruent(
                over: allDistinct, by: { $0.column < $1.column }, options: sanity)
        }
        #expect(failed(results, "StrictWeakOrdering.congruence"),
                "a generator with no equal pairs must not pass congruence")
    }

}
