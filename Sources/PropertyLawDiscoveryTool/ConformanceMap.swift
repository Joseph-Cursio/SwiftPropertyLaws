import PropertyLawCore

/// Cross-file conformance aggregation produced by `ModuleScanner` and
/// consumed by `GeneratedFileEmitter`. Entries are sorted by `typeName`
/// for stable output across runs (PRD §5.3 regeneration-as-diff guarantee).
struct ConformanceMap: Sendable, Equatable {

    struct Provenance: Sendable, Hashable, Comparable {
        /// Path passed to the scanner — typically relative to the package
        /// root when invoked via the plugin, absolute when invoked directly.
        let filePath: String
        let line: Int
        let kind: ProvenanceKind

        static func < (lhs: Provenance, rhs: Provenance) -> Bool {
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            if lhs.line != rhs.line { return lhs.line < rhs.line }
            return lhs.kind.rawValue < rhs.kind.rawValue
        }
    }

    enum ProvenanceKind: String, Sendable, Hashable {
        case primary           // struct / class / enum / actor declaration
        case `extension`       // `extension Foo: ...`
    }

    struct Entry: Sendable, Equatable {
        let typeName: String
        /// Most-specific surviving conformances per PRD §4.3 dedupe rule.
        let conformances: Set<KnownProtocol>
        let provenances: [Provenance]
        /// Generator-derivation choice (PRD §5.7) computed at scan time
        /// from the type's kind, inheritance clause, and whether any
        /// declaration in the module supplies `static func gen()`.
        let derivationStrategy: DerivationStrategy
        /// The module that **declares** this type, when it is not the scanned
        /// target — i.e. when the declaration was found in a context file the
        /// caller attributed to a module.
        ///
        /// `nil` means "this target", which is the common case and the one that
        /// needs no import beyond the `@testable import <Target>` already
        /// emitted. A non-`nil` value is what lets the emitter write the plain
        /// `import` a foreign type's suite needs to name it.
        let declaringModule: String?

        init(
            typeName: String,
            conformances: Set<KnownProtocol>,
            provenances: [Provenance],
            derivationStrategy: DerivationStrategy,
            declaringModule: String? = nil
        ) {
            self.typeName = typeName
            self.conformances = conformances
            self.provenances = provenances
            self.derivationStrategy = derivationStrategy
            self.declaringModule = declaringModule
        }
    }

    /// Sorted by `typeName` ascending.
    let entries: [Entry]

    /// Files the scanner couldn't parse — surfaced in the generated
    /// header so the user knows their output is partial.
    let parseFailures: [ParseFailure]

    /// Types the generated file could detect but not *use* — a suite for them
    /// would not compile, so none is emitted.
    ///
    /// Reported rather than silently dropped, for the same reason
    /// `parseFailures` is: a type that vanishes from the output with no
    /// explanation reads as "nothing to test here". Sorted by name.
    let skippedTypes: [SkippedType]

    /// Per-type witness signatures consumed by `AdvisorySuggester`
    /// (PRD §5.4). Keyed by the same `typeName` as `entries`; a missing
    /// key just means "no witnesses recorded" (e.g. extension-only
    /// declarations of stdlib types). Defaults to empty so the existing
    /// emitter call sites (which only need conformances) stay terse.
    let witnesses: [String: WitnessSet]

    /// Per-type function signatures consumed by `RoundTripSuggester`
    /// (PRD §5.5 M5 scope). Keyed by the same `typeName` as `entries`;
    /// missing key = no member functions worth recording (e.g. plain
    /// data types). Defaults to empty so non-advisory call sites stay
    /// terse.
    let memberFunctions: [String: [FunctionSignature]]

    /// Top-level free function signatures across all scanned files.
    /// Consumed by `RoundTripSuggester` for module-scope pairing
    /// (PRD §5.5: "in the same type or module"). Order is deterministic
    /// (file-path ascending, then declaration order).
    let topLevelFunctions: [FunctionSignature]

    /// The `TypeShape` per scanned type — the whole-module universe, retained
    /// so the scaffold pass can re-derive `.todo` types with a hole-filling
    /// resolver. Keyed by `typeName`. Defaults to empty for call sites that
    /// don't scaffold.
    let shapesByName: [String: TypeShape]

    /// Top-level user typealiases (`name` → underlying type spelling) collected
    /// from the scanned source, so the resolver can derive a member/parameter
    /// typed as an alias. Defaults to empty.
    let aliases: [String: String]

    struct ParseFailure: Sendable, Equatable {
        let filePath: String
        let message: String
    }

    init(
        entries: [Entry],
        parseFailures: [ParseFailure],
        skippedTypes: [SkippedType] = [],
        witnesses: [String: WitnessSet] = [:],
        memberFunctions: [String: [FunctionSignature]] = [:],
        topLevelFunctions: [FunctionSignature] = [],
        shapesByName: [String: TypeShape] = [:],
        aliases: [String: String] = [:]
    ) {
        self.entries = entries
        self.parseFailures = parseFailures
        self.skippedTypes = skippedTypes
        self.witnesses = witnesses
        self.memberFunctions = memberFunctions
        self.topLevelFunctions = topLevelFunctions
        self.shapesByName = shapesByName
        self.aliases = aliases
    }
}

/// A type the scanner detected but emitted no suite for. Top-level rather
/// than nested in `ConformanceMap` so `Reason` stays one level deep.
struct SkippedType: Sendable, Equatable {
    enum Reason: Sendable, Equatable {
        /// `private` / `fileprivate`, which `@testable import` does not
        /// promote the way it promotes `internal` — the suite could not
        /// even write `for: Thing.self`.
        case notNameable(AccessLevel)
        /// Declared in another module and not `public`. A foreign type is
        /// reachable only through a plain `import` — `@testable` is emitted for
        /// the scanned target alone, and across a package boundary it needs the
        /// dependency built with testability, which is not ours to assume — so
        /// anything narrower than `public` cannot be named however the imports
        /// are written.
        case foreignNonPublic(String)
        /// `public` or `open` with no `Sendable` conformance in sight.
        /// Swift infers `Sendable` for non-public types only, and every
        /// `check…PropertyLaws` entry point constrains its value to
        /// `Sendable`, so the call fails to type-check.
        case notSendable
    }

    let typeName: String
    let reason: Reason

    /// One-line explanation, shared by the file header and the CLI summary
    /// so the two never drift.
    var explanation: String {
        switch reason {
        case .notNameable(let level):
            return "declared `\(level.rawValue)` — not nameable from another file"
        case .foreignNonPublic(let module):
            return "declared in `\(module)` and not `public` — a foreign type "
                + "is only reachable through a plain import"
        case .notSendable:
            return "`public` without a `Sendable` conformance — "
                + "the law entry points require one"
        }
    }
}

/// One round-trip pair candidate emitted by `RoundTripSuggester`
/// (PRD §5.5 M5 scope). Output is informational only — never a test
/// failure, never a write to the generated file (preserves the M2
/// regeneration-as-diff guarantee).
struct RoundTripSuggestion: Sendable, Equatable {
    /// Where the pair was detected. Per-type and module-level scopes
    /// stay separate — a `Codec.encode` member doesn't pair with a
    /// top-level `decode` free function in M5.
    enum Scope: Sendable, Equatable, Hashable {
        case type(String)
        case module
    }
    let scope: Scope
    /// "Forward" half of the pair. When the names match an entry in
    /// `RoundTripSuggester.namePairs`, the table's `forward` slot wins;
    /// otherwise the alphabetically-earlier name takes the forward slot
    /// so output stays deterministic.
    let forward: FunctionSignature
    let backward: FunctionSignature
    let confidence: SuggestionConfidence
    /// Human-readable explanation of which signals fired (signature
    /// inverse, naming pair, `@Discoverable` group). Goes straight into
    /// the rendered diagnostic.
    let evidence: String
}

/// Syntactic record of one function declaration, consumed by
/// `RoundTripSuggester` (PRD §5.5 M5 scope) to look up inverse-typed
/// pairs.
///
/// Type names are stored as `TypeSyntax.trimmedDescription` strings —
/// the same syntactic-only stance `WitnessFinder` takes. Two types are
/// "the same" iff their textual forms match. Generic parameters are
/// rejected at the finder; they would require type-binding inference
/// out of M5's syntactic scope.
struct FunctionSignature: Sendable, Equatable {
    let name: String
    /// Parameter types in declaration order. Empty for `() -> U`.
    let parameterTypes: [String]
    /// `Void` when the declaration omits the return clause.
    let returnType: String
    let isStatic: Bool
    /// `group:` value from a `@Discoverable(group: "...")` attribute,
    /// when present and supplied as a string literal. Non-literal
    /// arguments leave this nil — see `RoundTripFinder` for the
    /// reasoning.
    let group: String?
}

/// Structural evidence that a type may want a particular conformance
/// (PRD §5.4 Advisory: missing-conformance suggestions, M4 scope).
///
/// Each flag is set when the corresponding declaration appears in the
/// type's own body or any of its same-module extensions. We deliberately
/// match on signature shape, not full type resolution — false positives
/// are possible but rare for these specific signatures, and the
/// suggester only emits HIGH-confidence advice by default.
struct WitnessSet: Sendable, Equatable {
    /// `static func ==(lhs:rhs:) -> Bool` — Equatable witness.
    var hasEqualEqualOperator: Bool = false
    /// `func hash(into:)` — Hashable witness.
    var hasHashIntoMethod: Bool = false
    /// `static func <(lhs:rhs:) -> Bool` — Comparable witness.
    var hasLessThanOperator: Bool = false
    /// `func encode(to:)` — Encodable half of the Codable pair.
    var hasEncodeToMethod: Bool = false
    /// `init(from:)` — Decodable half of the Codable pair.
    var hasInitFromInitializer: Bool = false

    /// Element-wise OR — used by the scanner to merge witnesses across
    /// primary decl + extensions in any order.
    mutating func merge(_ other: WitnessSet) {
        hasEqualEqualOperator     = hasEqualEqualOperator     || other.hasEqualEqualOperator
        hasHashIntoMethod         = hasHashIntoMethod         || other.hasHashIntoMethod
        hasLessThanOperator       = hasLessThanOperator       || other.hasLessThanOperator
        hasEncodeToMethod         = hasEncodeToMethod         || other.hasEncodeToMethod
        hasInitFromInitializer    = hasInitFromInitializer    || other.hasInitFromInitializer
    }
}
