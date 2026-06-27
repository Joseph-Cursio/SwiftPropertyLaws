/// Tier 1–3 of the generator-derivation strengthening (Idea #3): parse a
/// stored-member / init-parameter type spelling and compose
/// `swift-property-based` combinators around recognized raw types, known
/// value types, and — when a `resolve` closure is supplied — nested custom
/// types resolved through the whole-module type universe (Tier 3).
///
/// Kept beside `DerivationStrategy` as an extension on `DerivationStrategist`
/// so `memberGenerator` stays reachable from `memberwiseStrategy` and
/// `structTodoReason` (same module, internal access) without widening the
/// public surface beyond `ComposedGenerator`.
extension DerivationStrategist {

    /// A composed generator, backed by a structured `GeneratorPlan`.
    /// `expression` / `requiredImports` are derived from the plan, so the
    /// many call sites that read those keep working unchanged while the tree
    /// becomes available for scaffolding (holes) and refinement.
    public struct ComposedGenerator: Sendable, Equatable {
        public let plan: GeneratorPlan
        public var expression: String { plan.rendered }
        public var requiredImports: Set<String> { plan.requiredImports }

        public init(plan: GeneratorPlan) {
            self.plan = plan
        }

        /// Convenience for leaf generators (raw / known value types, and the
        /// resolver's inlined-or-`gen()` references).
        public init(expression: String, requiredImports: Set<String> = []) {
            self.plan = .leaf(expression: expression, imports: requiredImports)
        }
    }

    /// Resolves a bare custom-type spelling to a generator (Tier 3). The
    /// default resolves nothing — used by the macro path and any caller that
    /// only sees one type in isolation. The discovery plugin supplies a
    /// `GeneratorResolver` backed by the whole-module type universe.
    public typealias CustomTypeResolver = (String) -> ComposedGenerator?

    /// Generator expression for a stored-member type spelling. Convenience
    /// over `composedGenerator` for callers that don't need imports or
    /// custom-type resolution (the `.todo`-reason check, string-level tests).
    static func memberGenerator(forTypeName typeName: String) -> String? {
        composedGenerator(forTypeName: typeName)?.expression
    }

    /// Generator + required imports for a stored-member / init-parameter type
    /// spelling, composing `swift-property-based` combinators around
    /// recognized leaf types: `T?` → `.optional`, `[T]` → `.array(of:)`,
    /// `[K: V]` → `zip(...).dictionary(ofAtMost:)`, `Set<T>` →
    /// `.set(ofAtMost:)`. Recurses on element types so nested shapes
    /// (`[Int?]`, `[String: [Customer]]`) compose and carry imports up. A
    /// bare type that isn't a recognized raw/known value type is handed to
    /// `resolve` — `nil` by default (composite parsing only), or the
    /// whole-module resolver under the discovery plugin (Tier 3). Returns
    /// `nil` when the type doesn't bottom out in something derivable.
    static func composedGenerator(
        forTypeName typeName: String,
        resolve: CustomTypeResolver = { _ in nil }
    ) -> ComposedGenerator? {
        let text = trimmed(typeName)
        guard !text.isEmpty else { return nil }

        // Optional: `T?` sugar or `Optional<T>`.
        if text.hasSuffix("?") {
            return wrap(String(text.dropLast()), resolve: resolve) { .optional($0) }
        }
        if let inner = genericArgument(of: text, named: "Optional") {
            return wrap(inner, resolve: resolve) { .optional($0) }
        }

        // Array / Dictionary sugar: `[ ... ]`.
        if text.hasPrefix("["), text.hasSuffix("]") {
            let body = String(text.dropFirst().dropLast())
            if let colon = topLevelSeparatorIndex(in: body, separator: ":") {
                return dictionaryGenerator(
                    key: String(body[..<colon]),
                    value: String(body[body.index(after: colon)...]),
                    resolve: resolve
                )
            }
            return wrap(body, resolve: resolve) { .array($0) }
        }

        // Generic spellings: Array<T>, Set<T>, Dictionary<K, V>.
        if let inner = genericArgument(of: text, named: "Array") {
            return wrap(inner, resolve: resolve) { .array($0) }
        }
        if let inner = genericArgument(of: text, named: "Set") {
            return wrap(inner, resolve: resolve) { .set($0) }
        }
        if let inner = genericArgument(of: text, named: "Dictionary"),
           let comma = topLevelSeparatorIndex(in: inner, separator: ",") {
            return dictionaryGenerator(
                key: String(inner[..<comma]),
                value: String(inner[inner.index(after: comma)...]),
                resolve: resolve
            )
        }

        // Bare leaf: recognized raw / known value type, else custom-type
        // resolution (Tier 3).
        return leafGenerator(forTypeName: text, resolve: resolve)
    }

    /// Recurse into `inner`, then wrap its plan in the given collection node
    /// (`.optional` / `.array` / `.set`).
    private static func wrap(
        _ inner: String,
        resolve: CustomTypeResolver,
        _ node: (GeneratorPlan) -> GeneratorPlan
    ) -> ComposedGenerator? {
        composedGenerator(forTypeName: inner, resolve: resolve).map {
            ComposedGenerator(plan: node($0.plan))
        }
    }

    /// A `.dictionary` plan over the resolved key and value plans, or `nil`
    /// if either side doesn't resolve.
    private static func dictionaryGenerator(
        key: String,
        value: String,
        resolve: CustomTypeResolver
    ) -> ComposedGenerator? {
        guard let keyGen = composedGenerator(forTypeName: key, resolve: resolve),
              let valueGen = composedGenerator(forTypeName: value, resolve: resolve) else { return nil }
        return ComposedGenerator(plan: .dictionary(key: keyGen.plan, value: valueGen.plan))
    }

    /// A bare leaf type: a recognized stdlib raw type, a known value type
    /// with a curated engine generator, or — via `resolve` — a nested custom
    /// type (Tier 3). `nil` when none apply.
    private static func leafGenerator(
        forTypeName text: String,
        resolve: CustomTypeResolver
    ) -> ComposedGenerator? {
        if let raw = RawType(typeName: text) {
            return ComposedGenerator(expression: raw.generatorExpression)
        }
        if let known = knownValueGenerator(forTypeName: text) {
            return known
        }
        // Known stdlib/Foundation typealias → derive from the underlying type.
        // Factual resolution (e.g. TimeInterval *is* Double), not a guess.
        if let underlying = knownTypeAlias(text) {
            return composedGenerator(forTypeName: underlying, resolve: resolve)
        }
        return resolve(text)
    }

    /// Common stdlib/Foundation typealiases the scanner can't see the
    /// declaration of (they live in another module), mapped to their
    /// underlying type spelling. User-declared aliases are resolved
    /// separately, from the scanned source.
    private static func knownTypeAlias(_ text: String) -> String? {
        switch text {
        case "TimeInterval", "NSTimeInterval", "Float64":
            return "Double"
        case "Float32":
            return "Float"
        default:
            return nil
        }
    }

    /// Stdlib/Foundation value types outside the `RawRepresentable` raw-type
    /// set, each mapped to a curated `swift-property-based` generator and the
    /// modules its expression must name. Kept separate from `RawType`
    /// because `RawType` also drives `RawRepresentable` *enum* derivation.
    private static func knownValueGenerator(forTypeName text: String) -> ComposedGenerator? {
        switch text {
        case "Character":
            return ComposedGenerator(expression: "Gen<Character>.letterOrNumber")
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
