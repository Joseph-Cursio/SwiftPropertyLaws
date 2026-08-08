import PropertyBased

/// Curated generators for stdlib value types that sit outside the
/// `RawRepresentable` raw-type set and outside Foundation.
///
/// Same role as `FoundationGenerators`: derivation names these expressions from
/// `CompositeMemberParser.knownValueGenerator`, so a member or enum payload of
/// one of these types resolves instead of pinning its carrier at `.todo`.
extension Gen where Value == Unicode.Scalar {

    /// A `Unicode.Scalar` drawn across the ranges that actually break
    /// text-handling code, not just ASCII.
    ///
    /// **Weighted rather than uniform over the whole scalar space.** A uniform
    /// draw from `0 ... 0x10FFFF` is ~97% unassigned planes-3-to-13 code
    /// points: technically valid scalars that no realistic input contains, so
    /// the interesting boundaries — the ASCII/Latin-1 seam, the BMP edge, the
    /// astral plane where a scalar stops fitting in one UTF-16 code unit —
    /// would each be reached at negligible rates. The weights put every one of
    /// those in reach of a standard budget.
    ///
    /// **The surrogate range `0xD800 ... 0xDFFF` is excluded**, because
    /// `Unicode.Scalar(_:)` returns `nil` for it — those code points are not
    /// scalars. Drawing them would mean a `compactMap` that silently discards
    /// samples and skews the distribution it was meant to control.
    ///
    /// Fully seeded: both the band choice and the offset within it come from
    /// the engine's RNG.
    public static func unicodeScalar() -> Generator<Unicode.Scalar, some SendableSequenceType> {
        Gen<UInt32>.frequency(
            // ASCII — what most code is written and tested against.
            (4.0, Gen<UInt32>.uint32(in: 0x20 ... 0x7E)),
            // Latin-1 supplement and Latin Extended-A: accents and the first
            // place a byte-oriented assumption breaks.
            (2.0, Gen<UInt32>.uint32(in: 0x00A0 ... 0x017F)),
            // Below the surrogate block — the top of the safely-uniform BMP.
            (2.0, Gen<UInt32>.uint32(in: 0x0180 ... 0xD7FF)),
            // Above the surrogate block, to the BMP edge.
            (1.0, Gen<UInt32>.uint32(in: 0xE000 ... 0xFFFD)),
            // Astral: emoji and anything needing a surrogate pair in UTF-16.
            (1.0, Gen<UInt32>.uint32(in: 0x10000 ... 0x10FFFF))
        )
        .map { value in
            // Every band excludes the surrogate range by construction, so this
            // is total. It is a `precondition` and **not** a `?? U+FFFD`
            // fallback: a mutant that widened a band into the surrogate range
            // survived the test suite, because the fallback quietly rewrote
            // every invalid draw to the replacement character and the
            // distribution silently skewed instead of anything failing. A band
            // table that can produce a non-scalar is a bug in this file, and it
            // should say so.
            guard let scalar = Unicode.Scalar(value) else {
                preconditionFailure(
                    "unicodeScalar() drew \(value), which is not a Unicode scalar — "
                    + "a band in this generator overlaps the surrogate range "
                    + "0xD800...0xDFFF."
                )
            }
            return scalar
        }
    }
}
