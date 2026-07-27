/// Generator-derivation strategy for a single type — the result of
/// applying PRD §5.7's priority order to a syntax-agnostic `TypeShape`.
///
/// The macro and the discovery plugin both call `DerivationStrategist`
/// with their own `TypeShape` (built from SwiftSyntax in each case) and
/// emit identical generator-reference text from the returned strategy.
public enum DerivationStrategy: Sendable, Equatable {
    /// User explicitly defines `<TypeName>.gen()`. M1's convention; the
    /// emitter just references `<TypeName>.gen()` and the compiler resolves.
    case userGen

    /// `enum T: CaseIterable` — emit `Gen<T?>.element(of: T.allCases).compactMap { $0 }`
    /// (the Optional is load-bearing: `element(of:)` is `where Value == C.Element?`).
    case caseIterable

    /// PRD §5.7 Strategy 3 — every stored property of a struct resolves to
    /// a generator: a recognized stdlib raw type, or a composite of
    /// optional/array/set/dictionary around recognized raw types (Tier 1).
    /// The emitter composes per-member generators via `zip(...)` (or a
    /// single `.map(...)` for a 1-member type) and lifts through the type's
    /// synthesized memberwise initializer. v1 supports 1–10 members; arity
    /// 11+ falls through to `.todo` because `swift-property-based` ships
    /// `zip` overloads up to 10-arity.
    case memberwiseArbitrary(members: [MemberSpec])

    /// `enum T: <RawType>` where `RawType` is a stdlib type with a known
    /// generator (Int, String, Bool, …). The emitter lifts the raw-value
    /// generator through `T.init(rawValue:)` with a `compactMap` to drop
    /// `nil`s for sparse raw spaces.
    case rawRepresentable(RawType)

    /// Tier 6 — a struct with a user-defined initializer whose parameters
    /// all resolve to generators. Memberwise derivation can't apply (the
    /// user `init` suppresses Swift's synthesized memberwise init), so the
    /// emitter instead composes per-argument generators and lifts through
    /// that init: `zip(...).map { Type(label0: $0.0, ...) }`, honoring each
    /// argument's call label (or omitting it for an unlabeled `_` parameter).
    case initializerBased(arguments: [InitArgument])

    /// Tier 4 — an enum whose every case's associated values all resolve to
    /// generators (including payload-free cases). The emitter builds a
    /// `Generator<T>` per case (`Gen.always(T.c)` for payload-free, else
    /// `zip(...).map { T.c(...) }`) and combines them with
    /// `Gen.oneOf(...eraseToAny())`. Slots in after `rawRepresentable`, so
    /// `CaseIterable` and raw-value enums keep their simpler strategies; this
    /// fills the "enum without CaseIterable/raw" gap.
    case enumCases(cases: [EnumCaseGenerator])

    /// No strategy matched. The emitter produces a deliberate compile
    /// error pointing at where the user should provide `gen()` or annotate.
    /// `reason` carries a human-readable diagnostic surfaced as a macro
    /// warning alongside the compile error (PRD §5.7 telemetry).
    case todo(reason: String)

    /// Modules the emitted generator expression must be able to name (e.g.
    /// `["Foundation"]` when a member or init argument is a `Date`). The
    /// stdlib-only and `<Type>.gen()` strategies require none. The discovery
    /// plugin unions these across a target so the generated file imports what
    /// it references; the macro path ignores this (it expands where member
    /// types are already in scope).
    public var requiredImports: Set<String> {
        switch self {
        case .memberwiseArbitrary(let members):
            return members.reduce(into: Set<String>()) { $0.formUnion($1.requiredImports) }
        case .initializerBased(let arguments):
            return arguments.reduce(into: Set<String>()) { $0.formUnion($1.requiredImports) }
        case .enumCases(let cases):
            return cases.reduce(into: Set<String>()) { result, enumCase in
                for argument in enumCase.arguments { result.formUnion(argument.requiredImports) }
            }
        case .userGen, .caseIterable, .rawRepresentable, .todo:
            return []
        }
    }
}

/// Single member of a memberwise-derivation strategy: the stored property's
/// label paired with the `swift-property-based` generator expression that
/// produces values for it. The strategist returns `MemberSpec`s only after
/// every stored property has resolved to a generator (a recognized raw type,
/// or a composite of optional/array/set/dictionary around recognized raw
/// types); otherwise the strategy falls through to `.todo`.
public struct MemberSpec: Sendable, Equatable {
    public let name: String
    /// The recognized stdlib raw type when the member *is* a raw type;
    /// `nil` for composite members (optional/array/set/dictionary) and known
    /// value types, whose generator is composed in `generatorExpression`.
    public let rawType: RawType?
    /// The generator expression emitted for this member — the canonical
    /// field for emission. For raw members this equals
    /// `rawType.generatorExpression`; for composite/known members it composes
    /// engine combinators (`.optional`, `.array(of:)`, `.set(ofAtMost:)`,
    /// `zip(...).dictionary(ofAtMost:)`) and curated value-type generators.
    public let generatorExpression: String
    /// Modules `generatorExpression` must be able to name — e.g.
    /// `["Foundation"]` for a `Date` member. Empty for raw members and
    /// stdlib-only composites. Aggregated up to the discovery plugin so the
    /// generated file imports what it references.
    public let requiredImports: Set<String>

    /// Raw-member init. Keeps `rawType` populated and derives the
    /// expression from it — preserves the pre-Tier-1 construction shape so
    /// existing callers and equality assertions are unaffected.
    public init(name: String, rawType: RawType) {
        self.name = name
        self.rawType = rawType
        self.generatorExpression = rawType.generatorExpression
        self.requiredImports = []
    }

    /// Composite/known-member init. `rawType` is `nil`; the caller supplies
    /// the already-composed generator expression and any modules it names.
    public init(name: String, generatorExpression: String, requiredImports: Set<String> = []) {
        self.name = name
        self.rawType = nil
        self.generatorExpression = generatorExpression
        self.requiredImports = requiredImports
    }
}

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

    public init?(typeName: String) {
        guard let match = RawType.allCases.first(where: { $0.rawValue == typeName }) else {
            return nil
        }
        self = match
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

/// Stored property declared on a struct/class type — name + source-declared
/// type spelling. The macro and discovery plugin produce `[StoredMember]`
/// from SwiftSyntax independently; `DerivationStrategist` reads it for the
/// memberwise-Arbitrary strategy. Members whose type spelling doesn't
/// resolve to a `RawType` are still listed here — the strategist filters
/// and falls through to `.todo` if any one fails.
public struct StoredMember: Sendable, Equatable {
    public let name: String
    public let typeName: String

    public init(name: String, typeName: String) {
        self.name = name
        self.typeName = typeName
    }
}

/// Syntax-agnostic shape of a type declaration — built from SwiftSyntax
/// by the macro impl and the discovery plugin separately, consumed by
/// `DerivationStrategist` to choose a strategy.
public struct TypeShape: Sendable, Equatable {
    public enum Kind: String, Sendable, Equatable {
        case `struct`, `class`, `enum`, `actor`
    }

    public let name: String
    public let kind: Kind
    /// Inheritance-clause type names verbatim, in source order. Used to
    /// detect `CaseIterable`, `RawRepresentable` raw types, and (in
    /// future M3.5) member-conformance scanning.
    public let inheritedTypes: [String]
    /// Whether the user explicitly provides a `gen()` static method on
    /// the type or via an extension in the same file. The macro/plugin
    /// determines this from the surrounding source; the strategist
    /// honors it as the highest-priority strategy (Strategy A from
    /// PRD §5.7).
    public let hasUserGen: Bool
    /// Stored properties seen in the type's primary declaration, in
    /// source order. Empty for enums, actors, and any type whose
    /// primary body the macro/scanner couldn't see (e.g. extension-only
    /// types). The memberwise-Arbitrary strategy reads this.
    public let storedMembers: [StoredMember]
    /// `true` when the type's primary body contains any `init(...)`
    /// declaration. Swift suppresses the synthesized memberwise init in
    /// that case, so memberwise-Arbitrary derivation falls through to
    /// `.todo` — the synthesized init the strategy would call no longer
    /// exists. Inits declared in extensions don't suppress synthesis and
    /// don't set this flag.
    public let hasUserInit: Bool
    /// User-declared initializers captured from the type's primary body, in
    /// source order. Consumed by the Tier 6 `initializerBased` strategy when
    /// memberwise derivation can't apply. Empty when the scanner captured no
    /// init signatures (pre-Tier-6 callers, or a type with only the
    /// synthesized memberwise init).
    public let initializers: [InitializerSignature]
    /// Enum cases (name + associated values) captured from the primary body,
    /// in source order. Consumed by the Tier 4 `enumCases` strategy. Empty
    /// for non-enums and pre-Tier-4 callers.
    public let enumCases: [EnumCase]

    public init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        hasUserGen: Bool,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false,
        initializers: [InitializerSignature] = [],
        enumCases: [EnumCase] = []
    ) {
        self.name = name
        self.kind = kind
        self.inheritedTypes = inheritedTypes
        self.hasUserGen = hasUserGen
        self.storedMembers = storedMembers
        self.hasUserInit = hasUserInit
        self.initializers = initializers
        self.enumCases = enumCases
    }
}

/// Pure-logic strategist. Consumes a `TypeShape`, returns a
/// `DerivationStrategy`. No SwiftSyntax dependency — the syntax-to-shape
/// conversion lives in each consumer (macro impl, discovery tool).
public enum DerivationStrategist {

    /// Size of a single `zip` group. Bound by `swift-property-based`'s `zip`
    /// overloads, which ship for arities 2–10. Single-member types don't need
    /// `zip` at all — they go through `Generator.map` directly.
    public static let memberwiseArityLimit = 10

    /// Maximum number of stored properties (or init parameters) memberwise
    /// derivation supports. Members beyond `memberwiseArityLimit` are composed
    /// by **nesting**: chunk into groups of ≤`memberwiseArityLimit`, `zip` each
    /// group, `zip` the groups, then `.map` with nested tuple access
    /// (`$0.group.position`). The ceiling is `memberwiseArityLimit²` = 100
    /// (ten groups of ten) — the point at which the outer `zip` itself would
    /// exceed the 10-arity overload. Real value types rarely approach it; the
    /// app road-test hit ordinary 11–14-member structs the flat-10 limit refused.
    public static let memberwiseMemberLimit = memberwiseArityLimit * memberwiseArityLimit

    public static func strategy(
        for shape: TypeShape,
        resolve: CustomTypeResolver = { _ in nil }
    ) -> DerivationStrategy {
        // Priority order from PRD §5.7. Strategy A — explicit user-provided
        // `gen()` — wins unconditionally. Users who want a derived
        // generator simply don't define `gen()`.
        if shape.hasUserGen {
            return .userGen
        }
        if shape.kind == .enum, shape.inheritedTypes.contains("CaseIterable") {
            return .caseIterable
        }
        if let memberwise = memberwiseStrategy(for: shape, resolve: resolve) {
            return memberwise
        }
        if let initBased = initializerBasedStrategy(for: shape, resolve: resolve) {
            return initBased
        }
        // **Case enumeration BEFORE `rawRepresentable`, and this order is
        // load-bearing.**
        //
        // `.rawRepresentable` emits a *filter*:
        //
        //     Gen<Character>.letterOrNumber.string(of: 0...8)
        //         .compactMap { T(rawValue: $0) }
        //
        // — random raw values, kept only when they happen to name a case. For a
        // `String`-raw enum the odds are effectively zero and `compactMap`
        // retries forever; for an `Int`-raw enum drawing from the full `Int`
        // range they are worse. The generator does not terminate.
        //
        // That was not theoretical. SwiftInferProperties' self-dogfood road test
        // found two verifier binaries built from this recipe spinning at 99.9%
        // CPU for 46 and 71 minutes while the survey reported nothing at all —
        // the stub compiled and ran and simply never finished, which produces no
        // verdict, no error and no output. It was masked until then by a
        // *separate* consumer-side defect that stopped those stubs compiling; see
        // `docs/roadtest-self-dogfood.md` §11.2.1 in that repo.
        //
        // When the case list was captured, `.enumCases` enumerates it exactly
        // (`Gen.oneOf(Gen.always(T.a), Gen.always(T.b), …)`) — terminating,
        // uniform, and total over the enum. A raw-valued enum that also declares
        // `CaseIterable` never reaches either arm; it short-circuits above.
        if let enumStrategy = enumCasesStrategy(for: shape, resolve: resolve) {
            return enumStrategy
        }
        if shape.kind == .enum, let rawType = rawType(in: shape.inheritedTypes) {
            // Fallback only: the cases were not captured (an enum whose body the
            // scanner could not see), so there is nothing to enumerate.
            //
            // **This arm is still a filter and can still fail to terminate**, and
            // that is a known, bounded risk rather than an oversight. It is fine
            // where the raw domain is small and densely covered by cases — `Bool`,
            // a narrow `Int8` — and it is unusable where it is not, which is every
            // `String`-raw enum and any `Int`-raw enum drawn from the full range.
            // Narrowing it further would need a bounded-domain generator per raw
            // type, which is a real design change rather than a reordering.
            // Consumers should bound the run (SwiftInferProperties'
            // `VerifierSubprocess.defaultRunTimeout` does) so a non-terminating
            // generator surfaces as a verdict instead of a wedge.
            return .rawRepresentable(rawType)
        }
        return .todo(reason: todoReason(for: shape))
    }

    /// PRD §5.7 Strategy 3 — memberwise-Arbitrary composition. Returns
    /// `nil` (rather than `.todo`) when the strategy isn't applicable so
    /// `strategy(for:)` can fall through to later candidates.
    ///
    /// Applies only to structs (no class/actor support yet — both can
    /// have non-memberwise inits or reference semantics that complicate
    /// the contract). Falls through when:
    /// - The type has no stored members (would produce `Gen.always(Self())`,
    ///   pathological for property-based testing).
    /// - The type declares any user `init` in its primary body (Swift
    ///   suppresses the synthesized memberwise init in that case).
    /// - Any member's type doesn't resolve to a recognized `RawType`.
    /// - Member count exceeds `memberwiseArityLimit` (10).
    private static func memberwiseStrategy(
        for shape: TypeShape,
        resolve: CustomTypeResolver
    ) -> DerivationStrategy? {
        guard shape.kind == .struct else { return nil }
        guard !shape.storedMembers.isEmpty else { return nil }
        guard !shape.hasUserInit else { return nil }
        guard shape.storedMembers.count <= memberwiseMemberLimit else { return nil }
        var specs: [MemberSpec] = []
        for member in shape.storedMembers {
            if let rawType = RawType(typeName: member.typeName) {
                // Raw member — keep `rawType` populated (back-compat).
                specs.append(MemberSpec(name: member.name, rawType: rawType))
            } else if let composed = composedGenerator(forTypeName: member.typeName, resolve: resolve) {
                // Composite (optional/array/set/dictionary), known value type
                // (Character/Date), or a nested custom type (Tier 3) — carries
                // any required imports.
                specs.append(MemberSpec(
                    name: member.name,
                    generatorExpression: composed.expression,
                    requiredImports: composed.requiredImports
                ))
            } else {
                return nil
            }
        }
        return .memberwiseArbitrary(members: specs)
    }

    /// First inherited type whose name matches a recognized stdlib raw
    /// type. `nil` if none — the type is not a `RawRepresentable` enum
    /// the strategist knows how to derive.
    private static func rawType(in inheritedTypes: [String]) -> RawType? {
        for name in inheritedTypes {
            if let match = RawType(typeName: name) {
                return match
            }
        }
        return nil
    }

}
