// The stdlib raw types memberwise and `RawRepresentable` derivation know how
// to generate, and the generator expression each one maps to.
//
// Split out of `DerivationStrategy.swift` when that file passed SwiftLint's
// 400-line ceiling — the same move that produced `TodoReason.swift`. This is
// the table half of the strategist: adding support for a new raw type is a
// change here and nowhere else, and it is the file to open when asking "why
// didn't `Foo` derive?"

// `SwiftProjectLint`'s `parallel-list-drift` reports this enum against
// `MinimalCodableValue`, which holds these fourteen names and three more — `null`, `array`,
// `dictionary`. It is not drift, and the three it "lacks" are the reason. That enum is the tree
// `MinimalEncoder` produces, so its roster is fixed by `SingleValueEncodingContainer`'s overload
// set plus `encodeNil` and the two container shapes. This table is the stdlib types a derived
// generator can be *spelled* for. The fourteen agree because both are Swift's `Codable` scalars;
// the three do not carry over because none of them is a Swift type at all — `null` is the absence
// of a value, and an array or a dictionary is a container shape, so no `RawRepresentable.RawValue`
// and no memberwise member could ever be one.
//
// Recorded rather than suppressed silently: the rule is right that two lists agreeing on fourteen
// names did not reach that overlap by chance, and wrong only about what the agreement means.
// `SwiftProjectLint#190` is the general form.
//
// The `swiftprojectlint:disable:next parallel-list-drift` directive this paragraph used to
// carry is retired as of SwiftProjectLint#227, which taught the rule the distinction directly:
// `MinimalCodableValue` spells its cases `bool(Bool)`, `int(Int)`, `int8(Int8)` — the case names
// ARE their payload types, so it is a tagged union over Swift's scalars rather than a vocabulary
// anybody chose, and an overlap with a table of type names is guaranteed rather than evidence.
// The explanation above stays because it is why the fourteen agree; the suppression is gone
// because the rule no longer needs telling.
/// Recognized stdlib raw types for `RawRepresentable` derivation. Each
/// case maps to a generator the emitter can spell out inline.
public enum RawType: String, Sendable, Equatable, CaseIterable {
    case int = "Int"
    case string = "String"
    case bool = "Bool"
    case double = "Double"
    case float = "Float"
    case int8 = "Int8"
    case int16 = "Int16"
    case int32 = "Int32"
    case int64 = "Int64"
    case uint = "UInt"
    case uint8 = "UInt8"
    case uint16 = "UInt16"
    case uint32 = "UInt32"
    case uint64 = "UInt64"

    /// Recognises the bare spelling and its **module-qualified** form: `Swift.String` is
    /// `String`.
    ///
    /// Factual resolution, not a guess — `Swift` is the declaring module of every case in this
    /// table — and the same reasoning `CompositeMemberParser.knownTypeAlias` already applies to
    /// `TimeInterval`.
    ///
    /// **Hand-written Swift almost never writes `Swift.String`; generated code writes nothing
    /// else.** `swift-openapi-generator` fully-qualifies every type it emits, so a member typed
    /// `Swift.String` matched no case, its enclosing type became underivable, and the consumer
    /// reported an unsupported *carrier* — a claim that the carrier is exotic, about a `String`.
    /// Measured downstream on a generated client: **0 of 28 `codable-round-trip` carriers had a
    /// resolvable member tree, against 16 of 28 once the spelling is recognised.**
    ///
    /// **Only the `Swift.` prefix, and only over one dot.** A deeper path is a nested type, not a
    /// module qualifier, and any other prefix may name a user module — `MyModule.String` is a
    /// user type that must not be handed this table's `String` generator.
    public init?(typeName: String) {
        let candidate = RawType.unqualified(typeName)
        guard let match = RawType.allCases.first(where: { $0.rawValue == candidate }) else {
            return nil
        }
        self = match
    }

    /// `Swift.String` → `String`; everything else unchanged.
    static func unqualified(_ typeName: String) -> String {
        guard typeName.hasPrefix("Swift.") else { return typeName }
        let bare = String(typeName.dropFirst("Swift.".count))
        // `Swift.Foo.Bar` is a nested type inside the module, not a qualified leaf.
        return bare.contains(".") ? typeName : bare
    }

    /// `swift-property-based` generator factory expression for this raw
    /// type. The emitter inlines this into the lifted `compactMap`. Names
    /// match `Gen+Int.swift` / `Gen+Float.swift` / `Gen.swift` / `Gen+String.swift`
    /// in upstream `swift-property-based` 1.2.x.
    public var generatorExpression: String {
        switch self {
        case .int: return "Gen<Int>.int()"
        case .string: return "Gen<Character>.letterOrNumber.string(of: 0...8)"
        case .bool: return "Gen<Bool>.bool()"
        case .double: return "Gen<Double>.double(in: -1_000_000...1_000_000)"
        case .float: return "Gen<Float>.float(in: -1_000_000...1_000_000)"
        case .int8: return "Gen<Int8>.int8()"
        case .int16: return "Gen<Int16>.int16()"
        case .int32: return "Gen<Int32>.int32()"
        case .int64: return "Gen<Int64>.int64()"
        case .uint: return "Gen<UInt>.uint()"
        case .uint8: return "Gen<UInt8>.uint8()"
        case .uint16: return "Gen<UInt16>.uint16()"
        case .uint32: return "Gen<UInt32>.uint32()"
        case .uint64: return "Gen<UInt64>.uint64()"
        }
    }

    /// v3.2 — an *edge-biased* generator expression for the `String` raw
    /// type, or `nil` for every other case. `generatorExpression`'s String
    /// arm (`Gen<Character>.letterOrNumber.string`) is alphanumeric-only, so
    /// a property check over a string-processing function never sees the
    /// whitespace / newline / punctuation inputs that falsify structural
    /// string logic (YAML `- ` markers, indentation, trimming) — the check
    /// then false-passes. This mixes the alphanumeric baseline with curated structural tokens
    /// via `Gen.frequency`, so those counterexamples become reachable.
    ///
    /// ## The tokens are composed, not only drawn whole
    ///
    /// A first version offered each token as a complete value — `"#"` or `"- "` or nothing else —
    /// and that is not enough for the largest class of law this generator exists to serve.
    /// **An idempotence or involution law over a structural string function is falsified by the
    /// structure appearing TWICE**, and a catalogue of whole strings supplies each structure
    /// exactly once.
    ///
    /// Measured on `EditorFormatter.strippingHeadingMarkers` (SwiftPropertyLaws#42): its law is
    /// false — the strip is `^`-anchored, so `"# ## Title"` loses one marker run per application
    /// — and over the whole-string generator's entire reachable domain, 13 tokens plus every
    /// alphanumeric string of length 0–2, **the function changed 0 of 3 920 values.** Not rarely
    /// falsified: unfalsifiable, at any budget.
    ///
    /// So a token is also offered doubled (`$0 + $0`) and suffixed with a short alphanumeric
    /// filler. `"# "` doubled is `"# # "`, which the stripper takes to `"# "` and then to `""` —
    /// the witness class, reached by a mechanism rather than by adding the witness. The doubled
    /// arm carries the heaviest weight of the three token arms because repetition is the shape
    /// the whole-string version could not reach at all.
    ///
    /// Intended for the *top-level* carrier of a String property. Struct
    /// members keep `generatorExpression` (the plain form), so memberwise
    /// derivation and its goldens are unaffected. The expression targets
    /// `swift-property-based` 1.2.x (`Gen.frequency` / `Gen.element`); the
    /// consumer inlines it into a stub that imports `PropertyBased`.
    public var edgeBiasedGeneratorExpression: String? {
        edgeBiasedGeneratorExpression(subjectTokens: [])
    }

    /// v4.8 — ``edgeBiasedGeneratorExpression`` with the **subject's own** string literals mixed
    /// into its alphanumeric baseline. `subjectTokens: []` is byte-identical to the property.
    /// See ``subjectBaseline(_:)`` for what the tokens are for and why they go where they go.
    public func edgeBiasedGeneratorExpression(subjectTokens: [String]) -> String? {
        guard self == .string else { return nil }
        let edges = RawType.stringEdgeCases
            .map(RawType.swiftStringLiteral)
            .joined(separator: ", ")
        let token = "Gen<String?>.element(of: [\(edges)] as [String]).map { $0! }"
        let filler = "Gen<Character>.letterOrNumber.string(of: 0...4)"
        return "Gen.frequency("
            + "(3.0, \(RawType.subjectBaseline(subjectTokens))), "
            + "(1.0, \(token)), "
            + "(3.0, \(token).map { $0 + $0 }), "
            + "(1.0, zip(\(token), \(filler)).map { $0 + $1 })"
            + ")"
    }

    /// v4.6 — a **hostile** generator expression for the `String` raw type, or `nil` for every
    /// other case. Where ``edgeBiasedGeneratorExpression`` is tuned for *structural* string laws,
    /// this one is tuned for **totality**: the law that a function returns or throws for every
    /// input its type admits, and never traps.
    ///
    /// ## Two laws over `String` want different draws, and that is the whole point
    ///
    /// A generator tuned for coverage of the **type** is silently mistuned for coverage of the
    /// **law**. `edgeBiasedGeneratorExpression` exists because an idempotence law needed a
    /// *repetition* witness — `strippingHeadingMarkers` changed 0 of 3 920 values under the plain
    /// generator. Its token list is therefore YAML and Markdown markers, and it is correct for
    /// that purpose.
    ///
    /// **Measured on a totality law it is wrong for.** Six real trap classes planted in
    /// `WikilinkParser.parse`, 100 trials each
    /// (`SwiftInferProperties/docs/measurements/totality-generator-reach.md`):
    ///
    /// | trap fires on | edge-biased | hostile |
    /// |---|---|---|
    /// | empty input | caught | caught |
    /// | a newline | caught | caught |
    /// | a tab | caught | caught |
    /// | any non-ASCII scalar | **missed** | caught |
    /// | a `[[` delimiter | **missed** | caught |
    /// | length > 64 | **missed** | caught |
    ///
    /// **3 of 6 against 6 of 6, and the correct implementation passes under both** — a generator
    /// that failed everything would also score 6 of 6 and be worthless.
    ///
    /// The worst miss was the delimiter: `WikilinkParser` exists to parse `[[…]]`, so its real
    /// trap bugs live in bracket handling, and the edge-biased generator cannot produce a single
    /// bracket. And the three it caught were caught by coincidence — `""`, `"\n"` and `"\t"` are
    /// in ``stringEdgeCases`` because that list was curated for heading and sequence markers, not
    /// for totality. A different curation with equal claim to the name would have scored zero.
    ///
    /// ## Why this is a sibling rather than a wider `stringEdgeCases`
    ///
    /// Widening that list would re-tune a generator that is currently correct for its own law and
    /// move every idempotence golden with it. The laws are different, so the generators are.
    ///
    /// ## The three arms are the three classes the measurement found unreachable
    ///
    /// Delimiters and escapes, because a parser's traps live where its structure does; Latin-1,
    /// because the ASCII baseline never leaves ASCII; and a long ASCII draw, because a length
    /// assumption is invisible to a generator capped near 16. The alphanumeric baseline is kept
    /// so the run still spends most of its trials on ordinary input.
    public var hostileGeneratorExpression: String? {
        hostileGeneratorExpression(subjectTokens: [])
    }

    /// v4.8 — ``hostileGeneratorExpression`` with the **subject's own** string literals mixed into
    /// its alphanumeric baseline. `subjectTokens: []` is byte-identical to the property.
    public func hostileGeneratorExpression(subjectTokens: [String]) -> String? {
        guard self == .string else { return nil }
        let hostile = RawType.hostileTokens
            .map(RawType.swiftStringLiteral)
            .joined(separator: ", ")
        let token = "Gen<String?>.element(of: [\(hostile)] as [String]).map { $0! }"
        return "Gen.frequency("
            + "(3.0, \(RawType.subjectBaseline(subjectTokens))), "
            + "(3.0, \(token)), "
            + "(2.0, \(token).map { $0 + $0 }), "
            + "(1.0, Gen<Character>.latin1.string(of: 0...24)), "
            + "(1.0, Gen<Character>.ascii.string(of: 0...120))"
            + ")"
    }

    /// Most subject tokens a generator takes; a caller's longer list is truncated, not rejected.
    static let subjectTokenCap = 16

    /// The alphanumeric baseline arm, mixed with the SUBJECT's own string literals when there are any.
    ///
    /// ## What the curated lists cannot know
    ///
    /// ``stringEdgeCases`` and ``hostileTokens`` are tuned per LAW; neither knows the function under
    /// test. A parser's traps live in its own delimiters and an escaper's false laws in its own
    /// entities, and those are the string literals in its body. **Measured by SwiftInferProperties
    /// (`docs/plans/subject-literal-generation-scope.md`, `docs/measurements/funnel-mutation-check.md`
    /// §8):** mixing them in refuted 7 of 52 passing behaviour laws — all false laws a narrow
    /// generator hid (`&` → `&amp;` → `&amp;amp;`) — and, over 83 totality laws, hung one on a REAL
    /// defect: a Markdown block parser that looped forever on its own `"#"`, freezing the app it
    /// ships in on 29 of its bundled documents.
    ///
    /// ## Why the baseline arm, and not the token list
    ///
    /// Adding subject tokens to the curated list would dilute every curated token's share of draws,
    /// including the doubled `"# "` the edge-biased generator exists to reach. Replacing the
    /// baseline arm with *baseline, a subject token alone, a subject token embedded in random text*
    /// takes its share only from alphanumerics — and is **exactly the configuration that was
    /// measured**, so the numbers above are this code's. With no tokens it is the original arm,
    /// byte for byte.
    static func subjectBaseline(_ subjectTokens: [String]) -> String {
        let baseline = "Gen<Character>.letterOrNumber.string(of: 0...8)"
        var seen: Set<String> = []
        let tokens = subjectTokens.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(subjectTokenCap)
        guard !tokens.isEmpty else { return baseline }
        let literals = tokens.map(RawType.swiftStringLiteral).joined(separator: ", ")
        let subject = "Gen<String?>.element(of: [\(literals)] as [String]).map { $0! }"
        let short = "Gen<Character>.letterOrNumber.string(of: 0...4)"
        let embedded = "zip(zip(\(short), \(subject)).map { $0 + $1 }, \(short)).map { $0 + $1 }"
        return "Gen.frequency((2.0, \(baseline)), (1.0, \(subject)), (1.0, \(embedded)))"
    }

    /// Tokens a **parser** is most likely to trap on: the delimiters that carry structure, the
    /// escapes that carry meaning, and the empty and whitespace boundaries.
    ///
    /// Deliberately *general* rather than fitted to the subject that exposed the gap. The
    /// measurement used `WikilinkParser`, whose delimiter is `[[`, and a list containing only
    /// `[[` would score 6 of 6 on it and nothing on the next parser. Every parser has delimiters;
    /// no curated list contains all of them, so this covers the common families and the two
    /// unbounded arms — Latin-1 and length — carry what a list cannot.
    static let hostileTokens: [String] = [
        "", " ", "\n", "\t",
        "[", "]", "[[", "]]", "[[a]]", "[[a|b]]",
        "{", "}", "<", ">", "(", ")",
        "\"", "'", "\\", "|", "&", ";", "%", "$",
        "\u{0}", "\u{7F}"
    ]

    /// Curated **tokens** mixed with random strings, and composed rather than only drawn whole:
    /// empty / whitespace / newline boundaries plus the YAML and Markdown markers
    /// (`-`, `- `, leading-space `-`, `#`, `# `) that dominate real string-structural bugs.
    ///
    /// `"# "` joined `"-"`/`"- "` late, and its absence was a gap rather than a judgement. The
    /// list already carried four YAML sequence forms and the ATX marker only in its
    /// *non-triggering* spelling: a bare `"#"` does not match `^#{1,6}[ \t]+`, so a heading
    /// stripper is the identity on it. One markup family had its space form and the other did
    /// not.
    static let stringEdgeCases: [String] = [
        "", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "# ", "/"
    ]

    /// Uppercase hex without `String(format:)`, which lives in Foundation —
    /// **`PropertyLawCore` is a dependency-free leaf and stays one.**
    static func hexadecimal(_ value: UInt32) -> String {
        guard value != 0 else { return "0" }
        let digits = Array("0123456789ABCDEF")
        var remaining = value
        var out = ""
        while remaining > 0 {
            out.insert(digits[Int(remaining % 16)], at: out.startIndex)
            remaining /= 16
        }
        return out
    }

    /// Render `value` as a Swift double-quoted string literal, escaping the characters that
    /// would otherwise break the emitted source.
    ///
    /// **Non-printable scalars are escaped as `\u{…}`, and that arm was missing.** The four
    /// explicit cases below are the ones hand-written Swift actually contains, and for as long as
    /// every token in this file was typeable they were sufficient. `hostileTokens` introduced
    /// `\u{0}` and `\u{7F}` — a parser trapping on NUL is exactly the kind of bug a totality law
    /// is for — and those were written into the generated file as **raw bytes**: a literal NUL in
    /// a `.swift` source file.
    ///
    /// Caught by reading the emitted bytes rather than by any test, which is the lesson worth
    /// keeping: every assertion on this function compared *strings*, and a NUL inside a Swift
    /// string compares equal to itself perfectly well. `EmittedFileParsesTests`-style checks and
    /// the round-trip test added alongside this are what make the escape observable.
    static func swiftStringLiteral(_ value: String) -> String {
        var out = "\""
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            case "\r": out += "\\r"
            default:
                // A scalar Swift source cannot carry literally — control codes, DEL, and the
                // other non-printables — becomes its escape rather than its byte. NUL is
                // deliberately NOT given its own `\0` arm: `\u{0}` is equally valid Swift, and
                // one rule covering every non-printable is one thing to get right rather than a
                // list to keep in step with the token set.
                if let scalar = character.unicodeScalars.first,
                   character.unicodeScalars.count == 1,
                   scalar.properties.generalCategory == .control || scalar.value == 0x7F {
                    out += "\\u{\(Self.hexadecimal(scalar.value))}"
                } else {
                    out.append(character)
                }
            }
        }
        out += "\""
        return out
    }
}
