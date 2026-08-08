/// The syntax-agnostic description of a type that `DerivationStrategist`
/// consumes — and the stored-property record it is built from.
///
/// Split out of `DerivationStrategy.swift` to keep that file under the 400-line
/// lint, following the `RawType.swift` and `TodoReason.swift` precedent. This is
/// the *input* half of the strategist; `DerivationStrategy` is the output half.

/// Stored property declared on a struct/class type — name + source-declared
/// type spelling. The macro and discovery plugin produce `[StoredMember]`
/// from SwiftSyntax independently; `DerivationStrategist` reads it for the
/// memberwise-Arbitrary strategy. Members whose type spelling doesn't
/// resolve to a `RawType` are still listed here — the strategist filters
/// and falls through to `.todo` if any one fails.
public struct StoredMember: Sendable, Equatable {
    public let name: String
    public let typeName: String
    /// Access level as declared on the property. Governs the access level of
    /// the initializer Swift synthesizes, and so whether the memberwise
    /// strategy's emitted call can compile at all — see `AccessLevel` and
    /// `Collection.synthesizedMemberwiseInitAccess`.
    ///
    /// Defaults to `.internal`, which is both Swift's implicit level and the
    /// back-compatible value: a caller building shapes without access
    /// information gets exactly the pre-existing behaviour.
    public let accessLevel: AccessLevel

    public init(name: String, typeName: String, accessLevel: AccessLevel = .implicit) {
        self.name = name
        self.typeName = typeName
        self.accessLevel = accessLevel
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
    /// Access level declared on the type itself, as distinct from its members.
    ///
    /// A `private` or `fileprivate` type cannot be *named* from another file at
    /// all, so a generated suite for one can't say `for: Thing.self` — and
    /// unlike an `internal` type, `@testable import` does not promote it. The
    /// discovery plugin drops such types rather than emitting a suite that
    /// cannot compile; the peer macro, expanding in the same file, is
    /// unaffected. Defaults to `.implicit` for callers that don't track it.
    public let accessLevel: AccessLevel
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
    /// Whether the scanner actually saw this type **declared**, as opposed to
    /// only extended.
    ///
    /// A whole-module scan reaches types it cannot see the declaration of —
    /// `extension Array: Foo` in this target, or a sibling module's type
    /// extended here. Everything member-shaped is then empty, and `kind`
    /// carries the `.struct` default rather than knowledge, so a diagnostic
    /// that reads those fields describes a declaration that was never in front
    /// of it. Defaults to `true` for the macro path, which is always attached
    /// to a declaration.
    public let hasPrimaryDeclaration: Bool

    public init(
        name: String,
        kind: Kind,
        inheritedTypes: [String],
        hasUserGen: Bool,
        storedMembers: [StoredMember] = [],
        hasUserInit: Bool = false,
        initializers: [InitializerSignature] = [],
        enumCases: [EnumCase] = [],
        accessLevel: AccessLevel = .implicit,
        hasPrimaryDeclaration: Bool = true
    ) {
        self.hasPrimaryDeclaration = hasPrimaryDeclaration
        self.name = name
        self.kind = kind
        self.accessLevel = accessLevel
        self.inheritedTypes = inheritedTypes
        self.hasUserGen = hasUserGen
        self.storedMembers = storedMembers
        self.hasUserInit = hasUserInit
        self.initializers = initializers
        self.enumCases = enumCases
    }
}
