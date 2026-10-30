import Testing
@testable import PropertyLawKit

/// `LawIdentifier.allLawIdentifiers`, `allLawNames` and `isKnownLawName`: the
/// vocabulary of law names this module exports, checked against the laws its
/// suites actually emit.
struct LawVocabularyTests {

    /// `allLawNames` must contain every law the runtime actually emits, or a
    /// consumer validating its coverage claims against it gets false negatives
    /// — the failure mode the export exists to remove, reintroduced one layer
    /// up.
    ///
    /// Runs real suites rather than trusting `allCases`: the enums are the source
    /// of the set, so comparing the set to the enums would be circular.
    ///
    /// **The suites are chosen to span the enum split, not for convenience.**
    /// The first version of this test ran SetAlgebra, Equatable, Hashable and
    /// Comparable — all four covered by the original twelve enums, which were
    /// the only ones that existed. It passed while `isKnownLawName` returned
    /// `false` for every law of the other 27 protocols, because it confirmed the
    /// vocabulary against exactly the part of the kit the vocabulary was built
    /// from. AdditiveArithmetic and Numeric are here because they are outside
    /// that twelve; keep at least one such suite in this list.
    @Test func exportedVocabularyCoversEveryEmittedLaw() async throws {
        var emitted: Set<String> = []

        emitted.formUnion(try await checkSetAlgebraPropertyLaws(
            for: Set<Int>.self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...3).map(Set.init),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkEquatablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkHashablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkComparablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        // Outside the original twelve enums — the case the first version missed.
        emitted.formUnion(try await checkAdditiveArithmeticPropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkNumericPropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        #expect(!emitted.isEmpty, "no laws ran; the check below would pass vacuously")

        let unknown = emitted.filter { !LawIdentifier.isKnownLawName($0) }
        #expect(
            unknown.isEmpty,
            """
            These law names are emitted at runtime but absent from \
            LawIdentifier.allLawNames, so a consumer checking against it would \
            call them unknown: \(unknown.sorted().joined(separator: ", "))
            """
        )
    }

    /// The bracketed-backend case, which is the reason `allLawNames` holds base
    /// names and `isKnownLawName` exists at all. `CodableLaw` has one case and
    /// the runner emits `Codable.roundTripFidelity[<codec>]`, so a plain set
    /// membership test on the emitted name fails.
    @Test func backendSuffixIsStrippedBeforeMembership() {
        #expect(LawIdentifier.allLawNames.contains("Codable.roundTripFidelity"))
        #expect(!LawIdentifier.allLawNames.contains("Codable.roundTripFidelity[JSON]"))
        #expect(LawIdentifier.isKnownLawName("Codable.roundTripFidelity[JSON]"))
        #expect(LawIdentifier.baseName(of: "Codable.roundTripFidelity[JSON]")
                == "Codable.roundTripFidelity")
        #expect(LawIdentifier.baseName(of: "Equatable.reflexivity") == "Equatable.reflexivity")
    }

    /// The control. Without it, `isKnownLawName` returning true for everything
    /// would satisfy the two tests above.
    @Test func inventedLawNamesAreNotKnown() {
        #expect(!LawIdentifier.isKnownLawName("SetAlgebra.unionAssociativity"))
        #expect(!LawIdentifier.isKnownLawName("Equatable.notALaw"))
        #expect(!LawIdentifier.isKnownLawName(""))
    }

    /// The aggregate is assembled by hand, one `result +=` per law enum, so a
    /// dropped line silently shrinks the vocabulary.
    ///
    /// Counts distinct protocol names rather than summing every enum's
    /// `allCases`. Summing would mean listing all 39 enums here, which is the
    /// same hand-maintained list one file over and drifts the same way; one
    /// number fails just as loudly when a line goes missing, and adding a
    /// protocol is meant to be a deliberate edit in both places.
    @Test func vocabularyCoversEverySuiteThatShipsLaws() {
        let protocols = Set(LawIdentifier.allLawIdentifiers.map(\.protocolName))
        #expect(
            protocols.count == 40,
            """
            The vocabulary covers \(protocols.count) protocols, not 40. If a law \
            suite was added, add its enum to `allLawIdentifiers` and raise this \
            number; if one was removed, lower it. A silent drop here is the bug \
            that shipped in 4.3.0, where the aggregate covered twelve protocols \
            and claimed to cover all of them.
            """
        )
        #expect(
            LawIdentifier.allLawNames.count == LawIdentifier.allLawIdentifiers.count,
            "two law identifiers share a qualified name"
        )
    }
}
