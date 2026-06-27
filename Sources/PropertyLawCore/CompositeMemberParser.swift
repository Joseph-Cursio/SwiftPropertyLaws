/// Tier 1–2 of the generator-derivation strengthening (Idea #3): parse a
/// stored-member type spelling and compose `swift-property-based`
/// combinators around recognized raw types and known value types, instead
/// of exact-matching the whole spelling against `RawType` (which sent every
/// optional/array/set/dictionary member — and every `Date`/`Character`
/// member — to `.todo`).
///
/// Kept beside `DerivationStrategy` as an extension on `DerivationStrategist`
/// so `memberGenerator` stays reachable from `memberwiseStrategy` and
/// `structTodoReason` (same module, internal access) without widening the
/// public surface.
extension DerivationStrategist {

    /// A generator expression paired with the modules its source must be
    /// able to name. Threaded through composite parsing so the discovery
    /// plugin can emit the right `import`s into the *separate* generated
    /// file. The macro path needs no import handling — it expands in the
    /// type's own file, where every member type is already in scope.
    struct ComposedGenerator: Sendable, Equatable {
        let expression: String
        let requiredImports: Set<String>
    }

    /// Generator expression for a stored-member type spelling. Convenience
    /// over `composedGenerator` for callers that don't need import metadata
    /// (the `.todo`-reason check, and the existing string-level tests).
    static func memberGenerator(forTypeName typeName: String) -> String? {
        composedGenerator(forTypeName: typeName)?.expression
    }

    /// Generator + required imports for a stored-member type spelling,
    /// composing `swift-property-based` combinators around recognized leaf
    /// types: `T?` → `.optional`, `[T]` → `.array(of:)`, `[K: V]` →
    /// `zip(...).dictionary(ofAtMost:)`, `Set<T>` → `.set(ofAtMost:)`. Both
    /// the sugar (`[T]`, `T?`) and generic (`Array<T>`, `Optional<T>`,
    /// `Dictionary<K, V>`) spellings are recognized. Recurses on element
    /// types so nested shapes (`[Int?]`, `[String: [Int]]`, `Set<Date>?`)
    /// compose and carry their imports up. Returns `nil` when the type
    /// doesn't bottom out in a recognized leaf (e.g. a nested custom type —
    /// Tier 3, not yet supported).
    ///
    /// Default collection sizes use `0...8` — small enough to keep trials
    /// cheap and shrinking fast, large enough to exercise multi-element
    /// behavior.
    static func composedGenerator(forTypeName typeName: String) -> ComposedGenerator? {
        let text = trimmed(typeName)
        guard !text.isEmpty else { return nil }

        // Optional: `T?` sugar or `Optional<T>`.
        if text.hasSuffix("?") {
            return wrap(String(text.dropLast()), suffix: ".optional")
        }
        if let inner = genericArgument(of: text, named: "Optional") {
            return wrap(inner, suffix: ".optional")
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
            return wrap(body, suffix: ".array(of: 0...8)")
        }

        // Generic spellings: Array<T>, Set<T>, Dictionary<K, V>.
        if let inner = genericArgument(of: text, named: "Array") {
            return wrap(inner, suffix: ".array(of: 0...8)")
        }
        if let inner = genericArgument(of: text, named: "Set") {
            return wrap(inner, suffix: ".set(ofAtMost: 0...8)")
        }
        if let inner = genericArgument(of: text, named: "Dictionary"),
           let comma = topLevelSeparatorIndex(in: inner, separator: ",") {
            return dictionaryGenerator(
                key: String(inner[..<comma]),
                value: String(inner[inner.index(after: comma)...])
            )
        }

        // Bare leaf: recognized raw type or known value type.
        return leafGenerator(forTypeName: text)
    }

    /// Recurse into `inner`, append `suffix` to its generator expression,
    /// and carry the element's imports up unchanged.
    private static func wrap(_ inner: String, suffix: String) -> ComposedGenerator? {
        composedGenerator(forTypeName: inner).map {
            ComposedGenerator(
                expression: "\($0.expression)\(suffix)",
                requiredImports: $0.requiredImports
            )
        }
    }

    /// `zip(<keyGen>, <valGen>).dictionary(ofAtMost: 0...8)`, unioning both
    /// sides' imports, or `nil` if either side doesn't resolve.
    private static func dictionaryGenerator(key: String, value: String) -> ComposedGenerator? {
        guard let keyGen = composedGenerator(forTypeName: key),
              let valueGen = composedGenerator(forTypeName: value) else { return nil }
        return ComposedGenerator(
            expression: "zip(\(keyGen.expression), \(valueGen.expression)).dictionary(ofAtMost: 0...8)",
            requiredImports: keyGen.requiredImports.union(valueGen.requiredImports)
        )
    }

    /// A bare leaf type: a recognized stdlib raw type, or a known value type
    /// with a curated engine generator. `nil` for anything else.
    private static func leafGenerator(forTypeName text: String) -> ComposedGenerator? {
        if let raw = RawType(typeName: text) {
            return ComposedGenerator(expression: raw.generatorExpression, requiredImports: [])
        }
        return knownValueGenerator(forTypeName: text)
    }

    /// Stdlib/Foundation value types outside the `RawRepresentable` raw-type
    /// set, each mapped to a curated `swift-property-based` generator and the
    /// modules its expression must name. Kept separate from `RawType`
    /// because `RawType` also drives `RawRepresentable` *enum* derivation,
    /// where these don't belong.
    ///
    /// - `Character` → the engine's `letterOrNumber` character generator
    ///   (stdlib, no import).
    /// - `Date` → the engine's built-in `Gen<Date>.date` (shrinkable via
    ///   `Shrink.Integer`); names `Date`, so the generated file needs
    ///   `import Foundation`.
    private static func knownValueGenerator(forTypeName text: String) -> ComposedGenerator? {
        switch text {
        case "Character":
            return ComposedGenerator(expression: "Gen<Character>.letterOrNumber", requiredImports: [])
        case "Date":
            return ComposedGenerator(expression: "Gen<Date>.date", requiredImports: ["Foundation"])
        default:
            return nil
        }
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
