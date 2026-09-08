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

    /// The same 25 declarations as a bounded space, so the violator tests walk
    /// every pair and every triple instead of sampling them.
    ///
    /// These laws are conditional — asymmetry needs an ordered pair,
    /// transitivity a chain `x < y < z` — and whether a sample reaches such a
    /// case is luck. `nonTransitiveEquivalenceFails` was flaky for exactly that
    /// reason: its comparator's only chain is lines 0, 2, 4, which 100 draws
    /// miss about 45% of the time, and the vacuity guard correctly reported the
    /// resulting pass as meaningless. Walking the carrier makes each of these
    /// tests a statement about the comparator rather than about the draw.
    private func declSpace() -> Enumeration<Decl> {
        Every.elements("decl", in: (0...4).flatMap { line in (0...4).map { Decl(line: line, column: $0) } })
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
        // Walked, not sampled. `congruence` needs two values that are `==` and
        // not identical, and 25 distinct decls produce such a pair about once in
        // 25 draws — so at `.sanity` this test used to report a vacuous pass
        // roughly one run in twelve, which is the flake this carrier removes.
        // Over the walk the qualifying triples are there by construction.
        try await checkStrictWeakOrderingLaws(overEvery: declSpace(), by: byLineThenColumn)
        try await checkComparatorDiscriminates(
            overEvery: declSpace(), by: byLineThenColumn, distinct: { $0 != $1 })
        try await checkComparatorIsCongruent(overEvery: declSpace(), by: byLineThenColumn)
    }

    // MARK: - One violator per law

    @Test("irreflexivity catches `<=` written where `<` was meant")
    func nonStrictComparatorFails() async {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkStrictWeakOrderingLaws(
                overEvery: declSpace(), by: { $0.line <= $1.line })
        }
    }

    @Test("transitivity catches a comparator that is not an order at all")
    func intransitiveComparatorFails() async {
        // Orders by line modulo 3 — a cycle, so a < b < c < a.
        await #expect(throws: PropertyLawViolation.self) {
            try await checkStrictWeakOrderingLaws(
                overEvery: declSpace(),
                by: { ($0.line + 1) % 3 == $1.line % 3 })
        }
    }

    @Test("incomparability transitivity catches equivalence that is not one")
    func nonTransitiveEquivalenceFails() async {
        // "Within 1 of each other" is reflexive and symmetric and not transitive:
        // 0 ~ 1 and 1 ~ 2, but 0 is ordered against 2.
        await #expect(throws: PropertyLawViolation.self) {
            try await checkStrictWeakOrderingLaws(
                overEvery: declSpace(),
                by: { $1.line - $0.line > 1 })
        }
    }

    // MARK: - Walked rather than sampled

    /// A walked suite says how much of its input space it saw. A sampled one
    /// cannot, and reports `nil` — the distinction `SpaceCoverage` exists for.
    @Test("the walked suite reports complete coverage and the sampled one reports none")
    func walkedSuiteReportsCoverage() async throws {
        let byLineThenColumn: @Sendable (Decl, Decl) -> Bool = {
            $0.line != $1.line ? $0.line < $1.line : $0.column < $1.column
        }
        let walked = try await checkStrictWeakOrderingLaws(overEvery: declSpace(), by: byLineThenColumn)
        #expect(walked.allSatisfy { $0.coverage?.isComplete == true })
        // 25 decls, and the arity of each law is visible in its space size:
        // irreflexivity is unary (25), asymmetry binary (625), the two
        // transitivity laws ternary (15 625).
        #expect(Set(walked.compactMap { $0.coverage?.spaceSize }) == [25, 625, 15_625])

        let sampled = try await checkStrictWeakOrderingLaws(over: decls(), by: byLineThenColumn, options: sanity)
        #expect(sampled.allSatisfy { $0.coverage == nil })
    }

    /// **The two causes of a vacuous pass are different findings**, and only a
    /// complete walk tells them apart. Sampled, zero applications might be a
    /// narrow generator or a case that cannot exist. Walked completely, only the
    /// second reading survives — so the report stops advising a wider generator
    /// and states a fact about the carrier.
    @Test("a vacuous pass names the generator when sampled and the carrier when walked")
    func vacuityMessageDistinguishesItsTwoCauses() async throws {
        let compare: @Sendable (Int, Int) -> Bool = { $0 < $1 }

        var sampled: [CheckResult] = []
        await withKnownIssue("a constant generator cannot produce two distinct values") {
            sampled = try await checkComparatorDiscriminates(
                over: Gen<Int>.int(in: 0...0), by: compare, distinct: { $0 != $1 }, options: sanity)
        }
        let sampledText = sampled.first?.counterexample ?? ""
        #expect(sampledText.contains("the generator never produced"), "\(sampledText)")
        #expect(sampledText.contains("Widen the generator"))

        var walked: [CheckResult] = []
        await withKnownIssue("a one-element carrier holds no two distinct values") {
            walked = try await checkComparatorDiscriminates(
                overEvery: Every.elements("only", in: [42]), by: compare, distinct: { $0 != $1 })
        }
        let walkedText = walked.first?.counterexample ?? ""
        #expect(walkedText.contains("The walk was complete"), "\(walkedText)")
        #expect(walkedText.contains("property of the carrier"))
        #expect(walkedText.contains("no budget will help"))
        #expect(!walkedText.contains("the generator never produced"),
                "a walk has no generator to blame")
    }

    /// **The asymmetry that keeps vacuity a property of the law.** A complete
    /// walk sharpens the guard on three of the four conditional laws. On
    /// `incomparabilityTransitivity` the fact it would establish — no two cases
    /// in the carrier are incomparable — is the definition of a total order,
    /// which is a result rather than a defect. So that law stays unguarded even
    /// where the evidence is now conclusive.
    @Test("a total order walked in full is not reported vacuous")
    func totalOrderIsNotAVacuityFailure() async throws {
        // Distinct integers under `<`: no two are incomparable, so
        // `incomparabilityTransitivity`'s antecedent holds only for a value
        // against itself. A guard here would call that a defect.
        let results = try await checkStrictWeakOrderingLaws(
            overEvery: Every.elements("n", in: 0 ..< 6), by: { $0 < $1 })
        #expect(results.allSatisfy { !$0.isViolation })
        let incomparability = results.first { $0.protocolLaw.hasSuffix("incomparabilityTransitivity") }
        #expect(incomparability != nil)
        #expect(incomparability?.isViolation == false)
    }

    /// A walked failure reports **both** halves: the address says where in the
    /// space the case is, which is what makes it reproducible without a seed,
    /// and the law's own formatter says why it failed. Dropping either leaves a
    /// counterexample that is reproducible but unexplained, or explained but
    /// unlocatable.
    @Test("a walked counterexample carries the address and the law's explanation")
    func walkedCounterexampleCarriesBothHalves() async {
        var reported: String?
        do {
            _ = try await checkStrictWeakOrderingLaws(
                overEvery: declSpace(), by: { $0.line <= $1.line })
        } catch let violation as PropertyLawViolation {
            reported = violation.results.first { $0.protocolLaw.hasSuffix("irreflexivity") }?.counterexample
        } catch {}
        let text = try? #require(reported)
        #expect(text?.hasPrefix("decl=0:0 — ") == true, "missing the address: \(text ?? "nil")")
        #expect(text?.contains("compare(x, x) is true") == true, "missing the law's reason")
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
        try await checkStrictWeakOrderingLaws(overEvery: declSpace(), by: byLineOnly)

        // Reports — distinct declarations on one line are unordered. A Conventional
        // violation surfaces as a recorded issue rather than a throw, and
        // `withKnownIssue` fails if nothing is recorded, so this block IS the assertion.
        var results: [CheckResult] = []
        await withKnownIssue("discrimination fails at Conventional tier, by design") {
            results = try await checkComparatorDiscriminates(
                overEvery: declSpace(), by: byLineOnly, distinct: { $0 != $1 })
        }
        #expect(failed(results, "StrictWeakOrdering.discrimination"),
                "the line-only comparator must fail discrimination")
    }

    /// The other half of that: a comparator with deliberate equivalence classes
    /// must not be reported by the suite, which is why discrimination is opt-in.
    @Test("deliberate equivalence classes are not a suite failure")
    func groupingComparatorIsNotReportedBySuite() async throws {
        try await checkStrictWeakOrderingLaws(
            overEvery: declSpace(), by: { $0.line < $1.line })
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
