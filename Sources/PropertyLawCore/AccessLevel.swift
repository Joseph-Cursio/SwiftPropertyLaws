/// Access level as written in source, for the declarations the strategist has
/// to *call* rather than merely describe.
///
/// **Why this exists at all.** `InitializerBasedDerivation.takesPrivateStorage`
/// records the shortfall this closes: *"Access level would be the more direct
/// test, but `InitializerSignature` does not carry it."* There the `_`-prefix
/// label was an adequate proxy, because a storage parameter is conventionally
/// named. On the **synthesized memberwise** path there is no proxy available —
/// the initializer's parameter labels are the stored properties' real names, so
/// a `private` member is indistinguishable from a `public` one by name. The
/// modifier is sitting in the syntax; reading it is both cheaper and sound.
public enum AccessLevel: String, Sendable, Equatable, CaseIterable {
    case `private`
    case `fileprivate`
    case `internal`
    case package
    case `public`
    case open

    /// Swift's access level for a declaration carrying no modifier.
    public static let implicit: AccessLevel = .internal

    /// Maps a `DeclModifierSyntax` name to a level, or `nil` for the many
    /// modifiers that aren't about access (`static`, `final`, `lazy`, …).
    /// Callers pass the modifier's bare text; the caller is responsible for
    /// skipping detail-carrying modifiers — see `MemberBlockInspector`.
    public init?(modifierName: String) {
        guard let match = AccessLevel(rawValue: modifierName) else { return nil }
        self = match
    }
}

/// Where a consumer writes the code the strategist plans, relative to the type
/// being generated. Access control makes this observable, so the strategist
/// cannot decide reachability without it.
///
/// The two shipped consumers genuinely differ, and the difference is not
/// cosmetic — `fileprivate` is reachable from one and not the other:
///
/// - `@PropertyLawSuite` is a **peer** macro. Its expansion is attributed to
///   the file the type is declared in, at the type's own scope.
/// - The discovery plugin writes `Tests/<Target>Tests/PropertyLawTests.generated.swift`,
///   and `ScaffoldEmitter` writes a separate scaffold file. Both are other files.
public enum EmissionSite: String, Sendable, Equatable, CaseIterable {
    /// File scope of the type's own file — peer-macro expansion.
    case sameFile
    /// Any other file, in this module or a `@testable` importer of it.
    case separateFile
}

extension AccessLevel {

    /// Whether a declaration at this level can be *called* from `site`.
    ///
    /// Verified against the compiler on 2026-08-08 rather than argued from the
    /// language reference, because the `private` row is the counter-intuitive one:
    ///
    /// - `private` is scoped to the **enclosing declaration**, not the file. A
    ///   `private` memberwise initializer is therefore unreachable even from
    ///   file scope in the type's own file — `swiftc -typecheck` on a single
    ///   file reports *"initializer is inaccessible due to 'private' protection
    ///   level"*. Neither consumer can call it, so neither site is spared.
    /// - `fileprivate` is reachable from `.sameFile` and nowhere else.
    /// - `internal` and wider are reachable from both. `.separateFile` covers
    ///   the discovery plugin's test target, which reaches `internal` through
    ///   `@testable` — the mechanism the plugin's output already assumes.
    public func isCallable(from site: EmissionSite) -> Bool {
        switch self {
        case .private: return false
        case .fileprivate: return site == .sameFile
        case .internal, .package, .public, .open: return true
        }
    }
}

extension Collection where Element == StoredMember {

    /// Access level of the initializer Swift synthesizes for a struct with
    /// these stored properties: the **narrowest** member's level, since the
    /// synthesized init must not be able to leak a member it cannot name.
    ///
    /// Capped at `internal` — Swift never synthesizes a `public` memberwise
    /// init, so a struct of all-`public` members still gets an `internal` one.
    /// The cap is immaterial to `isCallable(from:)` (both answer `true`
    /// everywhere) but keeps the value honest for any future caller.
    ///
    /// An empty collection yields `internal`; memberwise derivation declines
    /// empty types before reaching here for an unrelated reason.
    var synthesizedMemberwiseInitAccess: AccessLevel {
        var narrowest = AccessLevel.internal
        for member in self where member.accessLevel.isNarrower(than: narrowest) {
            narrowest = member.accessLevel
        }
        return narrowest
    }

    /// First member whose access level makes the synthesized memberwise
    /// initializer uncallable from `site`. Drives the `.todo` diagnostic, which
    /// names the offending property rather than the type.
    func firstBlockingMemberwiseDerivation(from site: EmissionSite) -> StoredMember? {
        first { !$0.accessLevel.isCallable(from: site) }
    }
}

extension AccessLevel {

    /// Ordering by restrictiveness, `private` narrowest.
    func isNarrower(than other: AccessLevel) -> Bool {
        restrictivenessOrder < other.restrictivenessOrder
    }

    private var restrictivenessOrder: Int {
        switch self {
        case .private: return 0
        case .fileprivate: return 1
        case .internal: return 2
        case .package: return 3
        case .public: return 4
        case .open: return 5
        }
    }
}
