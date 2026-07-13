import Foundation
import Testing
import PropertyBased
@testable import PropertyLawKit

private struct Invoice: Codable, Equatable, Sendable {
    let identifier: Int
    let amount: Int
    let memo: String
}

extension Gen where Value == Invoice {
    static func invoice() -> Generator<Invoice, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0...10_000),
            Gen<Int>.int(in: -1_000...1_000),
            Gen<Character>.letterOrNumber.string(of: 0...8)
        ).map { identifier, amount, memo in
            Invoice(identifier: identifier, amount: amount, memo: memo)
        }
    }
}

/// The road-test's shape: a client DTO whose `Date` is carried over the wire as ISO-8601.
private struct FileResponse: Codable, Equatable, Sendable {
    let name: String
    let modifiedAt: Date
}

extension Gen where Value == FileResponse {
    /// Dates with **sub-second precision** — which is the whole point. A stock `.iso8601` formatter
    /// emits whole seconds, so the fractional part cannot survive the round trip.
    static func fileResponse() -> Generator<FileResponse, some SendableSequenceType> {
        zip(
            Gen<Character>.letterOrNumber.string(of: 1...8),
            Gen<Int>.int(in: 1...999)
        ).map { name, milliseconds in
            FileResponse(
                name: name,
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(milliseconds) / 1000)
            )
        }
    }
}

extension CodableCodec where T == FileResponse {
    /// Lossy by accident, not by design — the codec an app actually ships.
    static var iso8601: Self {
        Self(
            identifier: "JSON(iso8601)",
            encode: { value in
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                return try encoder.encode(value)
            },
            decode: { data in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode(FileResponse.self, from: data)
            }
        )
    }
}

struct CodableLawsTests {

    // MARK: - A5: a lossy codec must not be reported as passing

    @Test func lossyCodecUnderDefaultIsVisibleRatherThanSilent() async throws {
        // The bug this closes. `Codable.roundTripFidelity` is Conventional-tier, `.default` does not
        // throw on Conventional violations, and every entry point is `@discardableResult` — so the
        // idiomatic one-liner
        //
        //     checkCodablePropertyLaws(for: FileResponse.self, using: …, config: .init(codec: .iso8601))
        //
        // swallowed a genuine round-trip failure and read as a pass. `.iso8601` drops the fractional
        // seconds, so this DTO cannot survive its own codec.
        //
        // `withKnownIssue` fails if nothing is recorded, so this passing IS the assertion that the
        // violation now speaks.
        await withKnownIssue("a lossy codec must surface, even when it does not fail the test") {
            let results = try await checkCodablePropertyLaws(
                for: FileResponse.self,
                using: Gen<FileResponse>.fileResponse(),
                config: CodableLawConfig(codec: .iso8601),
                options: LawCheckOptions(budget: .sanity)
            )

            // It still does not throw — the tier semantics are intact — and it still reports the
            // violation in its returned results for anyone who reads them.
            #expect(results.count == 1)
            #expect(results[0].isViolation)
            #expect(results[0].tier == .conventional)
        }
    }

    @Test func lossyCodecStillFailsUnderStrict() async throws {
        await #expect(throws: PropertyLawViolation.self) {
            try await checkCodablePropertyLaws(
                for: FileResponse.self,
                using: Gen<FileResponse>.fileResponse(),
                config: CodableLawConfig(codec: .iso8601),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
    }

    @Test func intRoundTripsUnderStrict() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            config: CodableLawConfig(mode: .strict, codec: .json),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results[0].isViolation == false)
        #expect(results[0].tier == .conventional)
        #expect(results[0].protocolLaw == "Codable.roundTripFidelity[JSON]")
    }

    @Test func customStructRoundTripsUnderStrictJSON() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .strict, codec: .json),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results[0].isViolation == false, "Invoice should round-trip under JSON")
    }

    @Test func customStructRoundTripsUnderBinaryPlist() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .strict, codec: .binaryPlist),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results[0].isViolation == false)
        #expect(results[0].protocolLaw == "Codable.roundTripFidelity[PropertyList(binary)]")
    }

    @Test func semanticEquivalenceModeUsesCallerPredicate() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .semantic(equivalent: { _, _ in true })),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results[0].isViolation == false)
    }

    @Test func partialFieldsModeOnlyChecksListedFields() async throws {
        let results = try await checkCodablePropertyLaws(
            for: Invoice.self,
            using: Gen<Invoice>.invoice(),
            config: CodableLawConfig(mode: .partial(fields: [\Invoice.identifier, \Invoice.amount])),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results[0].isViolation == false)
    }
}
