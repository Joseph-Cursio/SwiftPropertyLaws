/// Tier 1 of the generator-derivation strengthening (Idea #3): parse a
/// stored-member type spelling and compose `swift-property-based`
/// combinators around recognized raw types, instead of exact-matching the
/// whole spelling against `RawType` (which sent every optional/array/
/// set/dictionary member to `.todo`).
///
/// Kept beside `DerivationStrategy` as an extension on `DerivationStrategist`
/// so `memberGenerator` stays reachable from `memberwiseStrategy` and
/// `structTodoReason` (same module, internal access) without widening the
/// public surface.
extension DerivationStrategist {

    /// Generator expression for a stored-member type spelling, composing
    /// `swift-property-based` combinators around recognized raw types:
    /// `T?` → `.optional`, `[T]` → `.array(of:)`, `[K: V]` →
    /// `zip(...).dictionary(ofAtMost:)`, `Set<T>` → `.set(ofAtMost:)`. Both
    /// the sugar (`[T]`, `T?`) and generic (`Array<T>`, `Optional<T>`,
    /// `Dictionary<K, V>`) spellings are recognized. Recurses on element
    /// types so nested shapes (`[Int?]`, `[String: [Int]]`, `Set<Int>?`)
    /// compose. Returns `nil` when the type doesn't bottom out in
    /// recognized raw types (e.g. a nested custom type — Tier 3, not yet
    /// supported).
    ///
    /// Default collection sizes use `0...8` — small enough to keep trials
    /// cheap and shrinking fast, large enough to exercise multi-element
    /// behavior.
    static func memberGenerator(forTypeName typeName: String) -> String? {
        let text = trimmed(typeName)
        guard !text.isEmpty else { return nil }

        // Optional: `T?` sugar or `Optional<T>`.
        if text.hasSuffix("?") {
            return memberGenerator(forTypeName: String(text.dropLast())).map { "\($0).optional" }
        }
        if let inner = genericArgument(of: text, named: "Optional") {
            return memberGenerator(forTypeName: inner).map { "\($0).optional" }
        }

        // Array / Dictionary sugar: `[ ... ]`.
        if text.hasPrefix("["), text.hasSuffix("]") {
            let body = String(text.dropFirst().dropLast())
            if let colon = topLevelSeparatorIndex(in: body, separator: ":") {
                return dictionaryGenerator(
                    key: String(body[..<colon]),
                    value: String(body[body.index(after: colon)...])
                )
            }
            return memberGenerator(forTypeName: body).map { "\($0).array(of: 0...8)" }
        }

        // Generic spellings: Array<T>, Set<T>, Dictionary<K, V>.
        if let inner = genericArgument(of: text, named: "Array") {
            return memberGenerator(forTypeName: inner).map { "\($0).array(of: 0...8)" }
        }
        if let inner = genericArgument(of: text, named: "Set") {
            return memberGenerator(forTypeName: inner).map { "\($0).set(ofAtMost: 0...8)" }
        }
        if let inner = genericArgument(of: text, named: "Dictionary"),
           let comma = topLevelSeparatorIndex(in: inner, separator: ",") {
            return dictionaryGenerator(
                key: String(inner[..<comma]),
                value: String(inner[inner.index(after: comma)...])
            )
        }

        // Bare recognized raw type.
        return RawType(typeName: text)?.generatorExpression
    }

    /// `zip(<keyGen>, <valGen>).dictionary(ofAtMost: 0...8)`, or `nil` if
    /// either side doesn't resolve.
    private static func dictionaryGenerator(key: String, value: String) -> String? {
        guard let keyGen = memberGenerator(forTypeName: key),
              let valueGen = memberGenerator(forTypeName: value) else { return nil }
        return "zip(\(keyGen), \(valueGen)).dictionary(ofAtMost: 0...8)"
    }

    /// The argument list inside `Name<...>` (e.g. `"K, V"` for
    /// `Dictionary<K, V>`), or `nil` if `text` isn't spelled that way.
    private static func genericArgument(of text: String, named name: String) -> String? {
        guard text.hasPrefix(name + "<"), text.hasSuffix(">") else { return nil }
        let start = text.index(text.startIndex, offsetBy: name.count + 1)
        return String(text[start..<text.index(before: text.endIndex)])
    }

    /// Index of the first `separator` at bracket/angle depth 0 in `text`,
    /// or `nil`. Respects `<>` and `[]` nesting so `[String: [Int: Int]]`
    /// splits at the outer colon only.
    private static func topLevelSeparatorIndex(
        in text: String,
        separator: Character
    ) -> String.Index? {
        var depth = 0
        var index = text.startIndex
        while index < text.endIndex {
            switch text[index] {
            case "<", "[": depth += 1
            case ">", "]": depth -= 1
            case separator where depth == 0: return index
            default: break
            }
            index = text.index(after: index)
        }
        return nil
    }

    /// Stdlib-only whitespace trim (avoids a Foundation dependency).
    private static func trimmed(_ value: String) -> String {
        var sub = Substring(value)
        while let first = sub.first, first == " " || first == "\t" || first == "\n" {
            sub = sub.dropFirst()
        }
        while let last = sub.last, last == " " || last == "\t" || last == "\n" {
            sub = sub.dropLast()
        }
        return String(sub)
    }
}
