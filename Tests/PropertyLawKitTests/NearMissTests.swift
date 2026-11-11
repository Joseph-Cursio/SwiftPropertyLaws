import Foundation
import PropertyBased
@testable import PropertyLawKit
import Testing

// MARK: - Test fixtures

/// Codable record whose `whitespaceField` is round-tripped through a custom
/// init that strips the leading whitespace. Under `.strict` this is a
/// violation; under `.semantic` (with a trim-aware predicate) or `.partial`
/// (listing only `id`) the law passes — but the per-field diff should surface
/// as a near-miss.
struct SemanticDriftRecord: Codable, Equatable, Sendable, CustomStringConvertible {
    let id: Int
    let whitespaceField: String

    init(id: Int, whitespaceField: String) {
        self.id = id
        self.whitespaceField = whitespaceField
    }

    enum CodingKeys: String, CodingKey { case id, whitespaceField }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(Int.self, forKey: .id)
        let raw = try container.decode(String.self, forKey: .whitespaceField)
        // The lossy step: strip a leading space if present.
        self.whitespaceField = raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(whitespaceField, forKey: .whitespaceField)
    }

    var description: String { "SDR(\(id), \"\(whitespaceField)\")" }
}

struct NearMissTests {

    // MARK: - Codable .semantic mode records field-level diffs as near-misses

    @Test func semanticRoundTripRecordsFieldDiffsAsNearMisses() async throws {
        // SemanticDriftRecord's `whitespaceField` round-trips with a leading
        // space stripped. Under `.semantic` equivalence we ignore that — but
        // the field-level diff should surface on `nearMisses`.
        let results = try await checkCodablePropertyLaws(
            for: SemanticDriftRecord.self,
            using: Gen<SemanticDriftRecord>.semanticDrift(),
            config: CodableLawConfig(
                mode: .semantic { lhs, rhs in
                    lhs.id == rhs.id
                        && lhs.whitespaceField.trimmingCharacters(in: .whitespaces)
                            == rhs.whitespaceField.trimmingCharacters(in: .whitespaces)
                }
            ),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        // Law passes via semantic equivalence.
        #expect(result.outcome == .passed)
        // Near-miss collector populated; mentions the whitespace field.
        let nearMisses = try #require(result.nearMisses)
        #expect(nearMisses.isEmpty == false, "expected at least one field diff")
        #expect(
            nearMisses.contains { $0.contains("whitespaceField") },
            "expected whitespaceField diff; got: \(nearMisses)"
        )
    }

    // MARK: - Codable .partial mode records non-listed-field diffs as near-misses

    @Test func partialRoundTripRecordsUnlistedFieldDiffs() async throws {
        // SemanticDriftRecord drops the leading space on whitespaceField. Under
        // `.partial` listing only `id`, the law passes but the whitespaceField
        // diff is a near-miss the reviewer should see.
        let results = try await checkCodablePropertyLaws(
            for: SemanticDriftRecord.self,
            using: Gen<SemanticDriftRecord>.semanticDrift(),
            config: CodableLawConfig(mode: .partial(fields: [\SemanticDriftRecord.id])),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        #expect(result.outcome == .passed)
        let nearMisses = try #require(result.nearMisses)
        #expect(
            nearMisses.contains { $0.contains("whitespaceField") },
            "expected whitespaceField diff in near-misses; got: \(nearMisses)"
        )
    }

    // MARK: - Codable .strict mode does NOT track field-level near-misses

    @Test func strictModeReportsNilNearMisses() async throws {
        // .strict mode treats any field diff as a violation. There are no
        // "near-misses" in that mode by design — `nearMisses` stays nil to
        // preserve the §4.6 "this law doesn't track near-misses" semantic.
        let results = try await checkCodablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            config: CodableLawConfig(mode: .strict),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        #expect(result.outcome == .passed)
        #expect(result.nearMisses == nil)
    }

    // MARK: - Clean run with no diffs reports an empty near-miss list, not nil

    @Test func cleanSemanticRunReportsEmptyNearMisses() async throws {
        // Int round-trips perfectly; `.semantic` accepts it and the mirror
        // walk finds no field diffs. nearMisses should be `[]`, not nil —
        // the collector ran but found nothing.
        let results = try await checkCodablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            config: CodableLawConfig(mode: .semantic { $0 == $1 }),
            options: LawCheckOptions(budget: .sanity)
        )
        let result = try #require(results.first)
        #expect(result.outcome == .passed)
        #expect(result.nearMisses?.isEmpty == true)
    }

    // MARK: - Collection.countConsistency records off-by-one diffs

    @Test func collectionCountOffByOneIsRecordedAsNearMiss() async throws {
        // OffByOneCountCollection lies count = stored + 1 — exactly the
        // off-by-one bug class. The violation triggers (Strict tier) AND
        // nearMisses carries the off-by-one tag.
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkCollectionPropertyLaws(
                for: OffByOneCountCollection.self,
                using: Gen<OffByOneCountCollection>.offByOneCount(),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let countResult = try #require(
            violation?.results.first { $0.protocolLaw == "Collection.countConsistency" }
        )
        let nearMisses = try #require(countResult.nearMisses)
        #expect(
            nearMisses.contains { $0.contains("off-by-one") },
            "expected off-by-one tag; got: \(nearMisses)"
        )
    }

    // Sequence.underestimatedCountLowerBound near-miss tracking is
    // intentionally not wired in M5 — the PRD §4.6 criterion is "off-by-one
    // on failure" but our existing planted bug fixture produces diffs of
    // magnitude 3–5, and most stdlib `Sequence`s are also `Collection`s
    // (where `underestimatedCount == count`, making any "tight" criterion
    // vacuous). Tracking deferred until either a real-world report or a
    // targeted planted-bug fixture surfaces.
}

extension Gen where Value == SemanticDriftRecord {
    static func semanticDrift() -> Generator<SemanticDriftRecord, some SendableSequenceType> {
        // Always prefix the field with a space so the lossy decode is
        // exercised on every trial.
        zip(Gen<Int>.int(in: 0...100), Gen<Character>.letterOrNumber.string(of: 1...4))
            .map { id, suffix in
                SemanticDriftRecord(id: id, whitespaceField: " \(suffix)")
            }
    }
}
