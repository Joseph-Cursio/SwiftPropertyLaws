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

/// The ASCII-restricted sibling of `unicodeScalar()`.
///
/// **Why a second generator rather than a narrower first one.** `unicodeScalar()` is right for
/// what it is for: text-handling code should be tested across the seams where byte-oriented
/// assumptions break. But a scalar is not always destined for text. When an initializer's
/// parameter is labelled `ascii:`, the label is a **domain declaration** — the API is telling
/// you it accepts a subset — and handing it the full scalar space is not a stronger test, it is
/// a guaranteed trap before the property is ever compared.
///
/// **Measured 2026-08-21 on `swift-system` @ `6a63f08`.** Derivation emitted
///
///     Gen<Unicode.Scalar>.unicodeScalar().map { SystemChar(ascii: $0) }
///
/// against `SystemString.swift:27`'s `internal init(ascii: Unicode.Scalar)`, which traps on
/// anything outside ASCII. Nine of the nineteen laws that reached the build stage compiled,
/// linked, ran, and died on `Fatal error: Code point value does not fit into ASCII` — the
/// single largest bucket in that survey, and every one of them evidence about the generator
/// rather than about the law. See `docs/measurements/criterion-a-swift-system.md` §2 in
/// SwiftInferProperties.
///
/// **Controls are included, and that is the point.** ASCII is `0x00 ... 0x7F`, not the
/// printable subset, and the interesting inputs for a path or parser library are exactly the
/// ones a "realistic" alphabet omits: NUL, the separators, tab and newline. Weighted so
/// printable characters dominate — a suite that is 90% control characters tests a different
/// program — with `\t`, `\n`, `\r` given their own band because they are the controls real
/// code actually branches on, and would otherwise be three draws in thirty-three.
///
/// Fully seeded: both the band choice and the offset within it come from the engine's RNG.
///
/// **Total by construction.** Every band lies inside `0 ... 0x7F`, which contains no surrogate
/// code points, so `Unicode.Scalar(UInt8)` — the non-failable overload — applies and no
/// `precondition` is needed. `unicodeScalar()` needs one because its bands are hand-written
/// against the surrogate hole; this one cannot reach it.
extension Gen where Value == Unicode.Scalar {

    public static func asciiScalar() -> Generator<Unicode.Scalar, some SendableSequenceType> {
        Gen<UInt8>.frequency(
            // Printable ASCII — space through `~`. What most code is written against.
            (6.0, Gen<UInt8>.uint8(in: 0x20 ... 0x7E)),
            // Tab, newline, carriage return: the controls real code branches on.
            // `element(of:)` is not used here: it vends an OPTIONAL, and a
            // `compactMap` back to non-optional would be three lines saying what
            // three equal-weight `always`es say plainly.
            (2.0, Gen<UInt8>.frequency(
                (1.0, Gen<UInt8>.always(0x09)),
                (1.0, Gen<UInt8>.always(0x0A)),
                (1.0, Gen<UInt8>.always(0x0D))
            )),
            // The rest of the control range, plus DEL. NUL is in here, which is what
            // makes this generator able to find a C-string truncation bug.
            (1.0, Gen<UInt8>.frequency(
                (1.0, Gen<UInt8>.uint8(in: 0x00 ... 0x08)),
                (1.0, Gen<UInt8>.uint8(in: 0x0B ... 0x1F)),
                (1.0, Gen<UInt8>.always(0x7F))
            ))
        )
        .map { Unicode.Scalar($0) }
    }
}
