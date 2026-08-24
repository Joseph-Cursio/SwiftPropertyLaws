/// The stdlib raw types memberwise and `RawRepresentable` derivation know how
/// to generate, and the generator expression each one maps to.
///
/// Split out of `DerivationStrategy.swift` when that file passed SwiftLint's
/// 400-line ceiling — the same move that produced `TodoReason.swift`. This is
/// the table half of the strategist: adding support for a new raw type is a
/// change here and nowhere else, and it is the file to open when asking "why
/// didn't `Foo` derive?"

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
    /// then false-passes. This mixes the alphanumeric baseline (weight 3)
    /// with curated structural edge strings (weight 2) via `Gen.frequency`,
    /// so those counterexamples become reachable.
    ///
    /// Intended for the *top-level* carrier of a String property. Struct
    /// members keep `generatorExpression` (the plain form), so memberwise
    /// derivation and its goldens are unaffected. The expression targets
    /// `swift-property-based` 1.2.x (`Gen.frequency` / `Gen.element`); the
    /// consumer inlines it into a stub that imports `PropertyBased`.
    public var edgeBiasedGeneratorExpression: String? {
        guard self == .string else { return nil }
        let edges = RawType.stringEdgeCases
            .map(RawType.swiftStringLiteral)
            .joined(separator: ", ")
        return "Gen.frequency("
            + "(3.0, Gen<Character>.letterOrNumber.string(of: 0...8)), "
            + "(2.0, Gen<String?>.element(of: [\(edges)] as [String]).map { $0! })"
            + ")"
    }

    /// Curated whole-string edge values injected alongside random strings:
    /// empty / whitespace / newline boundaries plus the YAML/markup tokens
    /// (`-`, `- `, leading-space `-`, multi-line) that dominate real
    /// string-structural bugs.
    static let stringEdgeCases: [String] = [
        "", " ", "  ", "\n", "\t", "-", "- ", "  -", "- x", "a\n- b", ":", "#", "/"
    ]

    /// Render `value` as a Swift double-quoted string literal, escaping the
    /// characters that would otherwise break the emitted source.
    static func swiftStringLiteral(_ value: String) -> String {
        var out = "\""
        for character in value {
            switch character {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n": out += "\\n"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        out += "\""
        return out
    }
}
