import Foundation
import PropertyBased

// Foundation-typed `Gen<T>` convenience generators, so kit users writing
// hand-authored property tests over Foundation types don't have to roll
// their own. See `docs/ideas/Foundation Generators.md`.
//
// The main line already imports Foundation (5 files), so these carry no new
// dependency and no swift-numerics footprint — Foundation is free here. They
// deliberately do NOT live in `PropertyLawComplex` (the opt-in swift-numerics
// line).
//
// All four are **fully seeded** (per the design note preferring a seeded form
// over the finite-path `doubleWithNaN` convention) so failures shrink
// reproducibly: every sampled value is a deterministic function of the
// backend's `SeededRandomNumberGenerator`.

extension Gen where Value == Date {
    /// A `Date` generator spanning years `1970 ... 2100`, without time
    /// components, in the UTC timezone.
    ///
    /// Wraps `swift-property-based`'s seeded `Gen<Date>.date(inYear:)`. The
    /// year window is fixed (not wall-clock-relative) so the sampled stream is
    /// stable across runs and machines — only the backend's shrink *direction*
    /// is clock-relative, which never changes which values are produced.
    public static func date() -> Generator<Date, some SendableSequenceType> {
        Gen<Date>.date(inYear: 1970 ... 2100)
    }
}

extension Gen where Value == UUID {
    /// A `UUID` generator producing RFC 4122 version-4 UUIDs from 16 seeded
    /// bytes.
    ///
    /// The 128 bits are drawn from the seeded RNG, then the version nibble
    /// (`0x40`) and variant bits (`0x80`) are stamped so every value is a
    /// well-formed v4 UUID. Fully seeded — same seed yields the same UUID
    /// stream.
    public static func uuid() -> Generator<UUID, some SendableSequenceType> {
        Gen<UInt8>.value().array(of: 16).map { sampledBytes -> UUID in
            var bytes = sampledBytes
            bytes[6] = (bytes[6] & 0x0F) | 0x40      // version 4
            bytes[8] = (bytes[8] & 0x3F) | 0x80      // RFC 4122 variant
            return bytes.withUnsafeBytes { buffer in
                UUID(uuid: buffer.load(as: uuid_t.self))
            }
        }
    }
}

extension Gen where Value == Data {
    /// A `Data` generator whose byte count is drawn from `count` and whose
    /// bytes are each seeded uniformly over `0 ... 255`.
    ///
    /// - Parameter count: The inclusive range of byte counts. Defaults to
    ///   `0 ... 256`. Pass a tighter range for size-controlled payloads.
    public static func data(of count: ClosedRange<Int> = 0 ... 256) -> Generator<Data, some SendableSequenceType> {
        Gen<UInt8>.value().array(of: count).map { bytes in Data(bytes) }
    }
}

extension Gen where Value == URL {
    /// Curated scheme components. Kept small and valid so composed URLs always
    /// parse — the design note is explicit that `url()` must yield only valid
    /// URLs rather than fuzzing arbitrary strings through `URL(string:)`.
    private static var urlSchemes: [String] { ["https", "http"] }

    /// Curated host components — registrable names plus `localhost`.
    private static var urlHosts: [String] {
        ["example.com", "example.org", "test.example", "localhost", "api.example.com"]
    }

    /// Curated path components. The empty entry yields a bare `scheme://host`.
    private static var urlPathSegments: [String] {
        ["", "path", "a/b", "users/42", "search", "docs/guide"]
    }

    /// A guaranteed-valid fallback. Only reachable if a curated component were
    /// edited into an unparseable combination — the single force-unwrap is on a
    /// constant literal and is provably safe.
    private static var fallbackURL: URL { URL(string: "https://example.com")! }

    /// A `URL` generator yielding only **valid** URLs, composed from curated
    /// scheme / host / path components indexed by three seeded draws.
    ///
    /// Fully seeded — the three index draws are the only entropy, so the URL
    /// stream is deterministic and shrinks through the underlying integer
    /// generators.
    public static func url() -> Generator<URL, some SendableSequenceType> {
        zip(
            Gen<Int>.int(in: 0 ..< urlSchemes.count),
            Gen<Int>.int(in: 0 ..< urlHosts.count),
            Gen<Int>.int(in: 0 ..< urlPathSegments.count)
        ).map { indices -> URL in
            let scheme = urlSchemes[indices.0]
            let host = urlHosts[indices.1]
            let segment = urlPathSegments[indices.2]
            let base = "\(scheme)://\(host)"
            let composed = segment.isEmpty ? base : "\(base)/\(segment)"
            return URL(string: composed) ?? fallbackURL
        }
    }
}
