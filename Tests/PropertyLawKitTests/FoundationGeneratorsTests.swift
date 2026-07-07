import Foundation
import PropertyBased
import Testing

@testable import PropertyLawKit

/// Verifies the kit-side contract for the Foundation-typed convenience
/// generators (`Gen.date()` / `Gen.uuid()` / `Gen.data(of:)` / `Gen.url()`)
/// per `docs/ideas/Foundation Generators.md`.
///
/// Each generator is checked for the two behaviors it promises: it produces
/// **valid** values of its type, and — because every one is fully seeded — the
/// **same seed yields an identical stream** (so failures shrink reproducibly).
struct FoundationGeneratorsTests {

    private static let trialCount = 1_000

    /// Walk a fresh Xoshiro for `trialCount` trials and collect every sample.
    private static func sample<Value, Shrinker: SendableSequenceType>(
        _ generator: Generator<Value, Shrinker>,
        seedTag: UInt64
    ) -> [Value] {
        var rng: any SeededRandomNumberGenerator =
            Xoshiro(seed: (seedTag, seedTag &+ 1, seedTag &+ 2, seedTag &+ 3))
        var out: [Value] = []
        out.reserveCapacity(trialCount)
        for _ in 0 ..< trialCount {
            out.append(generator.run(using: &rng))
        }
        return out
    }

    // MARK: - Date

    @Test
    func dateProducesValuesInTheFixedYearWindow() async throws {
        let samples = Self.sample(Gen<Date>.date(), seedTag: 1)
        let calendar = Calendar(identifier: .gregorian)
        for date in samples {
            let year = calendar.component(.year, from: date)
            // date(inYear: 1970...2100) is UTC; allow a one-year slop for the
            // local-calendar boundary at Jan 1 / Dec 31.
            #expect(year >= 1969 && year <= 2101, "date \(date) fell in year \(year), outside 1970...2100")
        }
    }

    @Test
    func dateIsDeterministicUnderTheSameSeed() async throws {
        let runA = Self.sample(Gen<Date>.date(), seedTag: 42)
        let runB = Self.sample(Gen<Date>.date(), seedTag: 42)
        #expect(runA == runB, "same seed produced divergent Date streams")
    }

    // MARK: - UUID

    @Test
    func uuidProducesWellFormedVersion4UUIDs() async throws {
        let samples = Self.sample(Gen<UUID>.uuid(), seedTag: 7)
        for uuid in samples {
            let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
            #expect(bytes.count == 16)
            #expect((bytes[6] & 0xF0) == 0x40, "byte 6 = \(bytes[6]): version nibble is not 4")
            #expect((bytes[8] & 0xC0) == 0x80, "byte 8 = \(bytes[8]): variant bits are not RFC 4122")
        }
    }

    @Test
    func uuidStreamHasHighDistinctness() async throws {
        let samples = Self.sample(Gen<UUID>.uuid(), seedTag: 8)
        let distinct = Set(samples)
        // 122 random bits — collisions across 1 000 draws are astronomically
        // unlikely; require all distinct.
        #expect(distinct.count == samples.count, "expected all-distinct UUIDs, got \(distinct.count)/\(samples.count)")
    }

    @Test
    func uuidIsDeterministicUnderTheSameSeed() async throws {
        let runA = Self.sample(Gen<UUID>.uuid(), seedTag: 99)
        let runB = Self.sample(Gen<UUID>.uuid(), seedTag: 99)
        #expect(runA == runB, "same seed produced divergent UUID streams")
    }

    // MARK: - Data

    @Test
    func dataRespectsTheRequestedSizeRange() async throws {
        let generator = Gen<Data>.data(of: 4 ... 12)
        let samples = Self.sample(generator, seedTag: 3)
        for data in samples {
            #expect(data.count >= 4 && data.count <= 12, "data count \(data.count) outside 4...12")
        }
    }

    @Test
    func dataDefaultRangeIsUsedWhenUnspecified() async throws {
        let samples = Self.sample(Gen<Data>.data(), seedTag: 5)
        for data in samples {
            #expect(data.count >= 0 && data.count <= 256, "data count \(data.count) outside default 0...256")
        }
    }

    @Test
    func dataIsDeterministicUnderTheSameSeed() async throws {
        let runA = Self.sample(Gen<Data>.data(of: 0 ... 64), seedTag: 11)
        let runB = Self.sample(Gen<Data>.data(of: 0 ... 64), seedTag: 11)
        #expect(runA == runB, "same seed produced divergent Data streams")
    }

    // MARK: - URL

    @Test
    func urlProducesOnlyValidURLs() async throws {
        let samples = Self.sample(Gen<URL>.url(), seedTag: 2)
        for url in samples {
            #expect(url.scheme == "https" || url.scheme == "http", "unexpected scheme in \(url)")
            #expect(url.host != nil, "URL \(url) has no host")
            // Round-trips through the string parser it was built with.
            #expect(URL(string: url.absoluteString) != nil, "URL \(url) does not re-parse")
        }
    }

    @Test
    func urlIsDeterministicUnderTheSameSeed() async throws {
        let runA = Self.sample(Gen<URL>.url(), seedTag: 77)
        let runB = Self.sample(Gen<URL>.url(), seedTag: 77)
        #expect(runA == runB, "same seed produced divergent URL streams")
    }
}
