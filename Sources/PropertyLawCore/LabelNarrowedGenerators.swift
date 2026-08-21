/// What does a parameter **label** tell you about the domain its generator should draw from?
///
/// Split out of `InitializerBasedDerivation.swift` on 2026-08-21, when adding the first rule
/// took that file to 401 lines against a 400-line cap. Relocated rather than trimmed — the
/// move this project makes for exactly this situation, and the seam is a real one: everything
/// else in the parent file answers *can this initializer be derived through at all*, and this
/// answers *given that it can, how wide should the draw be*.
///
/// Two label-driven rules now exist in the derivation, and they are worth reading together
/// because they use the same evidence for opposite purposes:
///
/// - `capacityHintLabels` reads a label to **reject** an initializer outright.
/// - `narrowedByLabel` reads one to **narrow** the generator chosen for a parameter.
///
/// Rejection is the stronger claim and its table is correspondingly conservative. Narrowing is
/// the safer direction — see the doc comment below.
extension DerivationStrategist {

    /// A parameter label can declare a **domain the type does not**.
    ///
    /// `capacityHintLabels` below reads a label to reject an initializer. This reads one to
    /// **narrow** the generator chosen for it, which is the same evidence used for a smaller
    /// claim: the type says what values are representable, and the label says which of them
    /// this API will accept.
    ///
    /// ## The measured case
    ///
    /// swift-system declares `internal init(ascii: Unicode.Scalar)` (`SystemString.swift:27`),
    /// which traps on anything outside ASCII. Derivation resolved the parameter by type alone
    /// and emitted
    ///
    ///     Gen<Unicode.Scalar>.unicodeScalar().map { SystemChar(ascii: $0) }
    ///
    /// pairing a full-Unicode generator with an ASCII-only initializer. `unicodeScalar()` draws
    /// ASCII about 4 times in 10 by design, so the trap is not a tail risk — it fires within a
    /// couple of trials, every run.
    ///
    /// **Measured 2026-08-21 on `swift-system` @ `6a63f08`** (SwiftInferProperties,
    /// `docs/measurements/criterion-a-swift-system.md` §2): of the 19 laws that reached the
    /// build stage, **9 compiled, linked, ran and died** on `Fatal error: Code point value does
    /// not fit into ASCII`. The largest single bucket in that survey, and every row of it
    /// evidence about the generator rather than about the law.
    ///
    /// ## Why this is not a slippery slope
    ///
    /// A label is weak evidence in general and this table is deliberately tiny. The bar for an
    /// entry is that the label names a **standard, checkable subset of the type** — `ascii` is
    /// `Unicode.Scalar.isASCII`, a property the stdlib itself vends — and not merely a hint
    /// about intent. `count`, `index`, `offset` and friends suggest ranges without defining
    /// them, and belong nowhere near here.
    ///
    /// Narrowing is also the safe direction. The worst case for a wrong entry is a generator
    /// that explores less than it could, which weakens a law. The worst case for the status quo
    /// is a process that traps before any law is compared, which produces nothing at all.
    ///
    /// Returns `resolved` unchanged whenever no rule applies, so every existing derivation
    /// emits byte-identical text.
    static func narrowedByLabel(
        _ resolved: ComposedGenerator,
        label: String?,
        typeName: String
    ) -> ComposedGenerator {
        guard let label, label == "ascii" else { return resolved }
        // Stdlib-only trim, matching this module's no-Foundation posture (see
        // `CompositeMemberParser.trimmed`, which is private to that file).
        let bare = String(typeName.drop(while: \.isWhitespace).reversed()
            .drop(while: \.isWhitespace).reversed())
        switch bare {
        case "Unicode.Scalar", "UnicodeScalar":
            return ComposedGenerator(
                expression: "Gen<Unicode.Scalar>.asciiScalar()",
                requiredImports: resolved.requiredImports
            )
        default:
            return resolved
        }
    }
}
