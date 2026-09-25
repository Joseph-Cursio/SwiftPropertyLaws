import PropertyLawCore

/// Confidence tier for an advisory suggestion (PRD §5.4).
///
/// M4 only emits `.high` — the syntactic detectors below are unambiguous
/// at the signatures they match. Lower tiers exist as API surface for
/// v1.1 detectors (semantic / heuristic) without requiring a CLI rev.
enum SuggestionConfidence: String, Sendable, Comparable {
    case low, medium, high

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }

    static func < (lhs: SuggestionConfidence, rhs: SuggestionConfidence) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// One missing-conformance hint emitted by `AdvisorySuggester`. Output
/// is informational only — never a test failure (PRD §5.4).
struct Suggestion: Sendable, Equatable {
    let typeName: String
    let suggestedProtocol: KnownProtocol
    let confidence: SuggestionConfidence
    /// Human-readable evidence — e.g. "defines `static func ==` and
    /// `func hash(into:)`". Goes straight into the rendered diagnostic.
    let evidence: String
}

/// Pure transform from `ConformanceMap` → `[Suggestion]`. The discovery
/// tool calls this only when `--advisory` is set; output goes to stderr,
/// never to the generated file (preserves regeneration-as-diff).
///
/// Detectors are deliberately conservative. PRD §8 sets a quality bar
/// of "less than 5% false-positive Strong-confidence suggestions" —
/// each detector below should be re-evaluated against that bar before
/// loosening the matcher.
enum AdvisorySuggester {

    /// Emit suggestions for every type in `map.witnesses` whose
    /// structural witnesses cross a HIGH-confidence threshold for a
    /// `KnownProtocol` it doesn't already conform to. Output is sorted
    /// for deterministic reporting.
    static func suggest(
        from map: ConformanceMap,
        minConfidence: SuggestionConfidence = .high
    ) -> [Suggestion] {
        let conformancesByType = Dictionary(
            uniqueKeysWithValues: map.entries.map { ($0.typeName, $0.conformances) }
        )

        var raw: [Suggestion] = []
        for (typeName, witnesses) in map.witnesses {
            let declared = conformancesByType[typeName] ?? []
            raw.append(contentsOf: detectors(for: typeName, witnesses: witnesses, declared: declared))
        }

        let resolved = applyHierarchyDedupe(raw)
        return resolved
            .filter { $0.confidence >= minConfidence }
            .sorted { lhs, rhs in
                if lhs.typeName != rhs.typeName { return lhs.typeName < rhs.typeName }
                return lhs.suggestedProtocol.rawValue < rhs.suggestedProtocol.rawValue
            }
    }

    /// All detector candidates for one type — pre-dedupe, pre-filter.
    private static func detectors(
        for typeName: String,
        witnesses: WitnessSet,
        declared: Set<KnownProtocol>
    ) -> [Suggestion] {
        var candidates: [Suggestion] = []

        // Codable: BOTH halves of the pair present, neither already declared.
        if witnesses.hasEncodeToMethod, witnesses.hasInitFromInitializer,
           !declared.contains(.codable) {
            candidates.append(Suggestion(
                typeName: typeName,
                suggestedProtocol: .codable,
                confidence: .high,
                evidence: "defines `func encode(to:)` and `init(from:)`"
            ))
        }

        // Equatable: `static func ==`, no Equatable already.
        // (Hashable / Comparable conformance also imply Equatable; the
        // hierarchy dedupe pass below removes Equatable when one of
        // those is being suggested.)
        if witnesses.hasEqualEqualOperator, !declared.contains(.equatable),
           !declared.contains(.hashable), !declared.contains(.comparable) {
            candidates.append(Suggestion(
                typeName: typeName,
                suggestedProtocol: .equatable,
                confidence: .high,
                evidence: "defines `static func ==`"
            ))
        }

        // Hashable: `func hash(into:)`, no Hashable already.
        if witnesses.hasHashIntoMethod, !declared.contains(.hashable) {
            candidates.append(Suggestion(
                typeName: typeName,
                suggestedProtocol: .hashable,
                confidence: .high,
                evidence: "defines `func hash(into:)`"
            ))
        }

        // Comparable: `static func <`, no Comparable already.
        if witnesses.hasLessThanOperator, !declared.contains(.comparable) {
            candidates.append(Suggestion(
                typeName: typeName,
                suggestedProtocol: .comparable,
                confidence: .high,
                evidence: "defines `static func <`"
            ))
        }

        return candidates
    }

    /// If both Hashable and Equatable, or both Comparable and Equatable,
    /// would be suggested for the same type, drop Equatable — Hashable
    /// and Comparable both subsume it in the stdlib hierarchy, so a user
    /// adopting either gets Equatable for free.
    static func applyHierarchyDedupe(_ suggestions: [Suggestion]) -> [Suggestion] {
        let suggestedByType = Dictionary(grouping: suggestions, by: \.typeName)
        var result: [Suggestion] = []
        for (_, group) in suggestedByType {
            let suggested = Set(group.map(\.suggestedProtocol))
            for suggestion in group {
                if suggestion.suggestedProtocol == .equatable,
                   suggested.contains(.hashable) || suggested.contains(.comparable) {
                    continue
                }
                result.append(suggestion)
            }
        }
        return result
    }
}

// `KnownProtocol.declarationName` is the canonical spelled-name accessor;
// `PropertyLawCore` owns it so this target and `PropertyLawMacroImpl` share one
// source of truth.
