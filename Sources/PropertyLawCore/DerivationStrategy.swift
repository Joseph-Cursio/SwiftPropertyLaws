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

    /// - Parameter emissionSite: where the caller will write the code this
    ///   strategy describes, which decides whether a `fileprivate` member is
    ///   reachable. Defaults to `.separateFile` — the conservative answer, and
    ///   the correct one for every consumer except the peer macro.
    public static func strategy(
        for shape: TypeShape,
        resolve: CustomTypeResolver = { _ in nil },
        emissionSite: EmissionSite = .separateFile
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
        if let memberwise = memberwiseStrategy(
            for: shape, resolve: resolve, emissionSite: emissionSite
        ) {
            return memberwise
        }
        if let initBased = initializerBasedStrategy(
            for: shape, resolve: resolve, emissionSite: emissionSite
        ) {
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
        // `SwiftInferProperties/docs/measurements/roadtest-self-dogfood.md` §11.2.1.
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
        return .todo(reason: todoReason(
            for: shape, emissionSite: emissionSite, resolve: resolve
        ))
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
    /// - A member's access level puts the synthesized init out of reach of
    ///   `emissionSite` (see below).
    ///
    /// **The access-level guard, and why it declines rather than warns.** Swift
    /// gives the synthesized memberwise initializer the access level of the
    /// *narrowest* stored property, so a restricted member makes the call this
    /// strategy emits uncompilable — see `AccessLevel.isCallable(from:)` for the
    /// per-site table and the compiler runs behind it.
    ///
    /// Emitting anyway produces *"initializer is inaccessible due to 'private'
    /// protection level"* against a generated file the header tells the user not
    /// to edit, taking the whole test target with it. `.todo` costs the same
    /// coverage and states the actual problem — the trade `takesPrivateStorage`
    /// already makes one tier down.
    private static func memberwiseStrategy(
        for shape: TypeShape,
        resolve: CustomTypeResolver,
        emissionSite: EmissionSite
    ) -> DerivationStrategy? {
        guard shape.kind == .struct else { return nil }
        guard !shape.storedMembers.isEmpty else { return nil }
        guard !shape.hasUserInit else { return nil }
        guard shape.storedMembers.count <= memberwiseMemberLimit else { return nil }
        guard shape.storedMembers
            .firstBlockingMemberwiseDerivation(from: emissionSite) == nil else { return nil }
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
