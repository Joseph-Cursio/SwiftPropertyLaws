import Testing
@testable import PropertyLawKit

/// The algebraic cluster driven over a bounded carrier instead of a generator.
///
/// This is the application Slice 1 was built for. Every law here is universally
/// quantified over two or three values of one carrier, so a carrier small enough
/// to walk turns "held for 1 000 random triples" into "holds" — with no budget
/// to choose and no combination left unreached.
@Suite("Algebraic laws over a walked carrier")
struct AlgebraicWalkedLawsTests {

    // MARK: - Fixtures

    /// Addition modulo 8: associative, commutative, identity `0`, and every
    /// element has an inverse. Conforms all the way down the `Group` chain.
    private struct Mod8: Group, Equatable, Sendable, CustomStringConvertible {
        let raw: Int
        static var identity: Mod8 { Mod8(raw: 0) }
        static func combine(_ lhs: Mod8, _ rhs: Mod8) -> Mod8 { Mod8(raw: (lhs.raw + rhs.raw) % 8) }
        static func inverse(_ value: Mod8) -> Mod8 { Mod8(raw: (8 - value.raw) % 8) }
        var description: String { "\(raw)" }
    }

    /// `max` over `0 ... 7`: associative, commutative, idempotent, identity `0`.
    private struct MaxSeven: Semilattice, Equatable, Sendable, CustomStringConvertible {
        let raw: Int
        static var identity: MaxSeven { MaxSeven(raw: 0) }
        static func combine(_ lhs: MaxSeven, _ rhs: MaxSeven) -> MaxSeven {
            MaxSeven(raw: max(lhs.raw, rhs.raw))
        }
        var description: String { "\(raw)" }
    }

    /// **A violator built to be rare rather than convenient.** Addition modulo
    /// 32 with one anomalous pair — `combine(29, 27)` returns `1` instead of
    /// `24`. One bad pair is enough to break associativity, but only for the
    /// triples that route through it: **122 of 32 768**, which
    /// `violationDensityIsWhatMakesThisWorthWalking` pins by brute force.
    ///
    /// At that density a sampled run misses it **69% of the time at `.sanity`**
    /// and 2.4% of the time at `.standard` — a CI flake rather than a failure.
    /// The walk finds it every time, at the smallest triple that proves it.
    private struct RarelyNonAssociative: Semigroup, Equatable, Sendable, CustomStringConvertible {
        let raw: Int
        static func combine(
            _ lhs: RarelyNonAssociative,
            _ rhs: RarelyNonAssociative
        ) -> RarelyNonAssociative {
            if lhs.raw == 29 && rhs.raw == 27 { return RarelyNonAssociative(raw: 1) }
            return RarelyNonAssociative(raw: (lhs.raw + rhs.raw) % 32)
        }
        var description: String { "\(raw)" }
    }

    private func mod8Carrier() -> Enumeration<Mod8> {
        Every.elements("value", in: (0 ..< 8).map { Mod8(raw: $0) })
    }

    private func maxSevenCarrier() -> Enumeration<MaxSeven> {
        Every.elements("value", in: (0 ..< 8).map { MaxSeven(raw: $0) })
    }

    private func rareCarrier() -> Enumeration<RarelyNonAssociative> {
        Every.elements("value", in: (0 ..< 32).map { RarelyNonAssociative(raw: $0) })
    }

    // MARK: - A correct carrier, walked

    @Test("a walked Semigroup suite covers every triple")
    func semigroupWalkIsComplete() async throws {
        let results = try await checkSemigroupPropertyLaws(overEvery: mod8Carrier())
        let coverage = try #require(results.first?.coverage)
        #expect(coverage.isComplete)
        #expect(coverage.spaceSize == 512, "8 values, one ternary law")
        #expect(results.allSatisfy { !$0.isViolation })
    }

    /// Inheritance still chains, and every inherited law is walked too — the
    /// shared assembler means the walked suite cannot run a different set of
    /// laws from the sampled one.
    @Test("a walked Group suite chains through Monoid and Semigroup")
    func groupWalkChainsInherited() async throws {
        let results = try await checkGroupPropertyLaws(overEvery: mod8Carrier())
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Semigroup.combineAssociativity"))
        #expect(names.contains("Monoid.combineLeftIdentity"))
        #expect(names.contains("Group.combineLeftInverse"))
        #expect(results.allSatisfy { $0.coverage?.isComplete == true },
                "every law in the chain must be walked, not just the outermost")
        #expect(results.allSatisfy { !$0.isViolation })
    }

    /// The longest chain in the cluster: Semilattice → CommutativeMonoid →
    /// Monoid → Semigroup. Law arity is visible in the coverage denominators.
    @Test("a walked Semilattice suite walks the whole chain")
    func semilatticeWalkChainsWholeCluster() async throws {
        let results = try await checkSemilatticePropertyLaws(overEvery: maxSevenCarrier())
        #expect(results.count == 5, "associativity, both identities, commutativity, idempotence")
        #expect(results.allSatisfy { $0.coverage?.isComplete == true })
        // Unary laws walk 8 cases, binary 64, ternary 512.
        #expect(Set(results.compactMap { $0.coverage?.spaceSize }) == [8, 64, 512])
        #expect(results.allSatisfy { !$0.isViolation })
    }

    @Test("ownOnly still skips the inherited laws when walked")
    func ownOnlyIsHonouredOnTheWalkedPath() async throws {
        let results = try await checkGroupPropertyLaws(overEvery: mod8Carrier(), laws: .ownOnly)
        #expect(results.map(\.protocolLaw) == ["Group.combineLeftInverse", "Group.combineRightInverse"])
    }

    /// `Ring` has no inheritance chain and eleven laws over two operations, so
    /// it exercises the flat half of the transform. `IntMod5` is the existing
    /// correct fixture from `RingLawsTests`.
    @Test("a walked Ring suite runs all eleven laws over every case")
    func ringWalkCoversEveryLaw() async throws {
        let carrier = Every.elements("value", in: (0 ..< 5).map { IntMod5(value: $0) })
        let results = try await checkRingPropertyLaws(overEvery: carrier)
        #expect(results.count == 11)
        #expect(results.allSatisfy { $0.coverage?.isComplete == true })
        // 5 values: unary laws walk 5, binary 25, ternary 125.
        #expect(Set(results.compactMap { $0.coverage?.spaceSize }) == [5, 25, 125])
        #expect(results.allSatisfy { !$0.isViolation })
    }

    // MARK: - The payoff

    /// **The number that makes walking worth the cost.** Brute-forced here so
    /// the sampling miss-rate quoted on `RarelyNonAssociative` is a computed
    /// fact rather than an assertion about a distribution.
    @Test("the planted violator is rare enough that sampling would miss it")
    func violationDensityIsWhatMakesThisWorthWalking() {
        let values = (0 ..< 32).map { RarelyNonAssociative(raw: $0) }
        var violating = 0
        for one in values {
            for two in values {
                for three in values {
                    let left = RarelyNonAssociative.combine(RarelyNonAssociative.combine(one, two), three)
                    let right = RarelyNonAssociative.combine(one, RarelyNonAssociative.combine(two, three))
                    if left != right { violating += 1 }
                }
            }
        }
        #expect(violating == 122, "density changed; the miss-rate in the doc comment is now wrong")
        // (1 - 122/32768)^100 ≈ 0.69 — a sampled `.sanity` run misses this
        // more often than it catches it.
        #expect(Double(violating) / 32_768 < 0.005)
    }

    /// The walk catches it, and names the *smallest* triple that proves it —
    /// not the smallest a shrinker descended to from a random starting point.
    @Test("walking finds the rare violator at its smallest witness")
    func walkFindsTheRareViolator() async {
        var reported: CheckResult?
        do {
            _ = try await checkSemigroupPropertyLaws(overEvery: rareCarrier())
        } catch let violation as PropertyLawViolation {
            reported = violation.results.first
        } catch {}
        let result = try? #require(reported)
        #expect(result?.isViolation == true)
        // Lexicographically first violating triple over 0 ..< 32.
        #expect(result?.counterexample?.hasPrefix("value=1 / value=28 / value=27 — ") == true,
                "got \(result?.counterexample ?? "nil")")
        #expect(result?.coverage?.spaceSize == 32_768)
    }
}
