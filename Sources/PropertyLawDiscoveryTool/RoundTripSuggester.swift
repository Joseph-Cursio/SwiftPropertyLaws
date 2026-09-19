/// Pure transform from `ConformanceMap` → `[RoundTripSuggestion]` for
/// PRD §5.5 cross-function round-trip discovery (M5 scope). The
/// discovery tool calls this only when `--advisory` is set; output
/// goes to stderr, never to the generated file (preserves the M2
/// regeneration-as-diff guarantee).
///
/// The detector is deliberately conservative — by default it only
/// emits HIGH-confidence pairs (signature inverse plus a matching
/// naming pair or `@Discoverable(group:)` value). MEDIUM and LOW are
/// available as enum cases so a caller that lowers `minConfidence`
/// gets surfaced through the same sort/dedupe pipeline.
enum RoundTripSuggester {

    /// Hand-curated list of name pairs that, combined with signature
    /// inversion, form a HIGH-confidence round-trip suggestion. Order
    /// inside each tuple is `(forward, backward)` — the suggestion
    /// presents the forward-named function first.
    ///
    /// Adding a new pair requires a maintainer commit, matching the
    /// PRD §5.6 stance for pattern lists. Avoid silent drift.
    static let namePairs: [(forward: String, backward: String)] = [
        ("encode", "decode"),
        ("serialize", "deserialize"),
        ("encrypt", "decrypt"),
        ("compress", "decompress"),
        ("marshal", "unmarshal"),
        ("pack", "unpack"),
        ("parse", "format"),
        ("push", "pop")
    ]

    /// Walk per-type member functions and module-level free functions
    /// in `map`, emitting every round-trip pair that meets
    /// `minConfidence`. Output is sorted for deterministic reporting.
    static func suggest(
        from map: ConformanceMap,
        minConfidence: SuggestionConfidence = .high
    ) -> [RoundTripSuggestion] {
        var raw: [RoundTripSuggestion] = []
        // Iterating sorted type names keeps the input to `pairs` stable
        // even though the final sort below would mask any per-type
        // ordering anyway. Sorted-keys is the cheaper, clearer guarantee.
        for typeName in map.memberFunctions.keys.sorted() {
            let functions = map.memberFunctions[typeName] ?? []
            raw.append(contentsOf: pairs(in: functions, scope: .type(typeName)))
        }
        raw.append(contentsOf: pairs(in: map.topLevelFunctions, scope: .module))
        return raw
            .filter { $0.confidence >= minConfidence }
            .sorted(by: Self.compare)
    }

    /// Generate every pair within a single scope. The
    /// `firstIndex < secondIndex` iteration gives symmetric dedupe for
    /// free — each unordered pair is seen exactly once.
    private static func pairs(
        in functions: [FunctionSignature],
        scope: RoundTripSuggestion.Scope
    ) -> [RoundTripSuggestion] {
        guard functions.count >= 2 else { return [] }
        var result: [RoundTripSuggestion] = []
        for firstIndex in functions.indices {
            for secondIndex in functions.indices where secondIndex > firstIndex {
                let pairing = pair(
                    functions[firstIndex],
                    functions[secondIndex],
                    scope: scope
                )
                if let pairing { result.append(pairing) }
            }
        }
        return result
    }

    /// Decide whether two functions form a round-trip pair candidate
    /// and at what confidence. Returns nil when neither signature
    /// inversion nor a naming/group signal fires.
    private static func pair(
        _ first: FunctionSignature,
        _ second: FunctionSignature,
        scope: RoundTripSuggestion.Scope
    ) -> RoundTripSuggestion? {
        let signatureInverse = isSignatureInverse(first, second)
        let namedPair = namePair(first.name, second.name)
        let groupMatch = first.group != nil && first.group == second.group

        guard signatureInverse || namedPair != nil || groupMatch else {
            return nil
        }

        let confidence: SuggestionConfidence
        if signatureInverse && (namedPair != nil || groupMatch) {
            confidence = .high
        } else if signatureInverse {
            confidence = .medium
        } else {
            confidence = .low
        }

        let (forward, backward) = orient(first, second, namedPair: namedPair)
        return RoundTripSuggestion(
            scope: scope,
            forward: forward,
            backward: backward,
            confidence: confidence,
            evidence: evidence(
                forward: forward,
                backward: backward,
                signatureInverse: signatureInverse,
                namedPair: namedPair,
                groupMatch: groupMatch
            )
        )
    }

    /// Single-arg signature inversion: `f: (T) -> U` paired with
    /// `g: (U) -> T`. M5 stays in the single-arg case — multi-arg
    /// "round trips" don't have a clean syntactic shape and would need
    /// type-binding inference.
    private static func isSignatureInverse(
        _ first: FunctionSignature,
        _ second: FunctionSignature
    ) -> Bool {
        guard first.parameterTypes.count == 1, second.parameterTypes.count == 1 else {
            return false
        }
        return first.parameterTypes[0] == second.returnType
            && second.parameterTypes[0] == first.returnType
    }

    /// Look up `(firstName, secondName)` (or its reverse) in
    /// `namePairs`. Returns the matching tuple in canonical
    /// (forward, backward) order, or nil when no entry matches.
    private static func namePair(
        _ firstName: String,
        _ secondName: String
    ) -> (forward: String, backward: String)? {
        for entry in namePairs {
            if entry.forward == firstName && entry.backward == secondName { return entry }
            if entry.forward == secondName && entry.backward == firstName { return entry }
        }
        return nil
    }

    /// Pick which of the two functions is "forward" in the emitted
    /// suggestion. The named-pair table wins when it matches; otherwise
    /// we fall back to alphabetical order on the function names so
    /// output stays deterministic.
    private static func orient(
        _ first: FunctionSignature,
        _ second: FunctionSignature,
        namedPair: (forward: String, backward: String)?
    ) -> (FunctionSignature, FunctionSignature) {
        if let named = namedPair {
            return first.name == named.forward ? (first, second) : (second, first)
        }
        return first.name <= second.name ? (first, second) : (second, first)
    }

    private static func evidence(
        forward: FunctionSignature,
        backward: FunctionSignature,
        signatureInverse: Bool,
        namedPair: (forward: String, backward: String)?,
        groupMatch: Bool
    ) -> String {
        var parts: [String] = []
        if signatureInverse {
            parts.append(
                "signature inverse "
                + "(\(forward.parameterTypes[0]) → \(forward.returnType), "
                + "\(backward.parameterTypes[0]) → \(backward.returnType))"
            )
        }
        if let named = namedPair {
            parts.append("name pair (\(named.forward)/\(named.backward))")
        }
        if groupMatch, let group = forward.group {
            parts.append("@Discoverable(group: \"\(group)\")")
        }
        return parts.joined(separator: " + ")
    }

    /// Sort: per-type scopes first (alphabetical by type name), then
    /// module scope, then forward-name asc, then backward-name asc.
    /// Same lex-order pattern as `AdvisorySuggester` for consistency.
    static func compare(
        _ lhs: RoundTripSuggestion,
        _ rhs: RoundTripSuggestion
    ) -> Bool {
        let leftKey = scopeKey(lhs.scope)
        let rightKey = scopeKey(rhs.scope)
        if leftKey != rightKey { return leftKey < rightKey }
        if lhs.forward.name != rhs.forward.name {
            return lhs.forward.name < rhs.forward.name
        }
        return lhs.backward.name < rhs.backward.name
    }

    private static func scopeKey(_ scope: RoundTripSuggestion.Scope) -> String {
        switch scope {
        case .type(let name): return "0:\(name)"
        case .module:         return "1:"
        }
    }
}
