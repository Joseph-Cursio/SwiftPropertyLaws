import Testing
@testable import PropertyLawCore

/// Swift gives the synthesized memberwise initializer the access level of the
/// narrowest stored property. Memberwise derivation calls that initializer, so a
/// restricted member makes the emitted expression uncompilable — not wrong, but
/// unbuildable, which in a `DO NOT EDIT` generated file breaks the whole test
/// target rather than one entry.
///
/// **Verified against the compiler on 2026-08-08**, because two of the three rows
/// are counter-intuitive:
///
/// | member | synthesized init | same file (peer macro) | other file (plugin) |
/// |---|---|---|---|
/// | `private let x` | `private` | **rejected** | rejected |
/// | `fileprivate let x` | `fileprivate` | accepted | **rejected** |
/// | `private(set) var x` | `internal` | accepted | accepted |
///
/// The `private` row is the surprising one: `private` scopes to the enclosing
/// *declaration*, not the file, so even a peer declaration beside the type is
/// out of reach. The `private(set)` row is the trap in the other direction —
/// it spells `private` and restricts nothing the initializer needs.
struct AccessLevelDerivationTests {

    private func shape(_ members: [StoredMember]) -> TypeShape {
        TypeShape(
            name: "Subject",
            kind: .struct,
            inheritedTypes: ["Equatable", "Hashable"],
            hasUserGen: false,
            storedMembers: members
        )
    }

    private func member(
        _ name: String,
        _ type: String = "Int",
        _ access: AccessLevel = .implicit
    ) -> StoredMember {
        StoredMember(name: name, typeName: type, accessLevel: access)
    }

    // MARK: - The guard

    /// The demonstrated defect: before this rule the strategist emitted
    /// `Subject(a: $0.0, secret: $0.1)` for exactly this shape.
    @Test("a private stored property declines memberwise derivation at either site")
    func privateMemberDeclinesEverywhere() {
        let subject = shape([member("a"), member("secret", "Int", .private)])
        for site in EmissionSite.allCases {
            guard case .todo = DerivationStrategist.strategy(
                for: subject, emissionSite: site
            ) else {
                Issue.record("expected .todo at \(site), got a derived strategy")
                return
            }
        }
    }

    /// The peer macro writes into the type's own file, so `fileprivate` is in
    /// reach. Declining it here would be a regression against code that
    /// compiles today — the reason the site is threaded rather than assumed.
    @Test("a fileprivate stored property still derives for same-file emission")
    func fileprivateMemberDerivesInSameFile() {
        let subject = shape([member("a"), member("b", "Int", .fileprivate)])
        guard case .memberwiseArbitrary(let members) = DerivationStrategist.strategy(
            for: subject, emissionSite: .sameFile
        ) else {
            Issue.record("expected memberwise derivation for same-file emission")
            return
        }
        #expect(members.map(\.name) == ["a", "b"])
    }

    /// Same shape, other file: the discovery plugin's generated test cannot
    /// name that initializer.
    @Test("a fileprivate stored property declines for separate-file emission")
    func fileprivateMemberDeclinesInSeparateFile() {
        let subject = shape([member("a"), member("b", "Int", .fileprivate)])
        guard case .todo = DerivationStrategist.strategy(
            for: subject, emissionSite: .separateFile
        ) else {
            Issue.record("expected .todo for separate-file emission")
            return
        }
    }

    /// `.separateFile` is the default precisely so a caller that knows nothing
    /// about access — including every downstream consumer of the public
    /// `strategy(for:resolve:)` — gets the conservative answer.
    @Test("the default emission site is the conservative one")
    func defaultSiteIsSeparateFile() {
        let subject = shape([member("a"), member("b", "Int", .fileprivate)])
        let defaulted = DerivationStrategist.strategy(for: subject)
        #expect(defaulted == DerivationStrategist.strategy(
            for: subject, emissionSite: .separateFile
        ))
    }

    // MARK: - What must keep working

    /// The false-negative direction. A rule that read the modifier name alone
    /// would decline this, costing a derivable type for a spelling.
    @Test("private(set) is not an access restriction on the initializer")
    func privateSetStillDerives() {
        // `MemberBlockInspector` maps `private(set) var` to `.implicit`; this
        // asserts the strategist honours that rather than re-deriving it.
        let subject = shape([member("a"), member("b", "Int", .implicit)])
        guard case .memberwiseArbitrary = DerivationStrategist.strategy(for: subject) else {
            Issue.record("expected memberwise derivation")
            return
        }
    }

    @Test("wider-than-internal members derive unchanged", arguments: [
        AccessLevel.internal, .package, .public, .open
    ])
    func widerAccessDerives(_ access: AccessLevel) {
        let subject = shape([member("a", "Int", access), member("b", "String", access)])
        for site in EmissionSite.allCases {
            guard case .memberwiseArbitrary = DerivationStrategist.strategy(
                for: subject, emissionSite: site
            ) else {
                Issue.record("expected memberwise derivation for \(access) at \(site)")
                return
            }
        }
    }

    /// Shapes built without access information are the pre-existing world; the
    /// defaulted parameter has to leave them exactly as they were.
    @Test("omitting the access level preserves the previous behaviour")
    func defaultedAccessLevelIsBackCompatible() {
        let untyped = StoredMember(name: "a", typeName: "Int")
        #expect(untyped.accessLevel == .internal)
        #expect(untyped == StoredMember(name: "a", typeName: "Int", accessLevel: .internal))
    }

    // MARK: - The diagnostic

    /// A `.todo` that says "memberwise derivation didn't apply" sends the user
    /// looking at member *types*. Naming the property and the level is the
    /// whole gain over letting the compiler reject the generated file.
    @Test("the todo reason names the property, its level, and the reach problem")
    func todoReasonIsSpecific() {
        let subject = shape([member("a"), member("secret", "Int", .private)])
        guard case .todo(let reason) = DerivationStrategist.strategy(for: subject) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("`secret`"))
        #expect(reason.contains("`private`"))
        #expect(reason.contains("memberwise initializer"))
        #expect(reason.contains("Widen the property's access level"))
        #expect(reason.contains("static func gen()"))
    }

    /// The two sites fail for different reasons and say so — a `fileprivate`
    /// member is not "unreachable", it is unreachable *from another file*, and
    /// that phrasing is what tells the user the macro would have worked.
    @Test("the fileprivate diagnostic attributes the failure to the other file")
    func fileprivateReasonNamesTheFile() {
        let subject = shape([member("a"), member("b", "Int", .fileprivate)])
        guard case .todo(let reason) = DerivationStrategist.strategy(
            for: subject, emissionSite: .separateFile
        ) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("being in another file"))
    }

    /// Ordering the diagnostic behind the type check would report a resolvable
    /// member as unrecognized when both problems are present.
    @Test("access is reported ahead of an unrecognized member type")
    func accessOutranksUnknownType() {
        let subject = shape([
            member("secret", "Int", .private),
            member("opaque", "SomeUnknownType")
        ])
        guard case .todo(let reason) = DerivationStrategist.strategy(for: subject) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("`secret`"))
        #expect(!reason.contains("no recognized stdlib raw type"))
    }

    // MARK: - The access model itself

    @Test("the synthesized init takes the narrowest member's level")
    func narrowestMemberWins() {
        #expect([
            member("a", "Int", .public),
            member("b", "Int", .fileprivate),
            member("c", "Int", .internal)
        ].synthesizedMemberwiseInitAccess == .fileprivate)
    }

    /// Swift never synthesizes a `public` memberwise init, so all-public
    /// members still yield `internal`.
    @Test("the synthesized init is capped at internal")
    func cappedAtInternal() {
        #expect([
            member("a", "Int", .public),
            member("b", "Int", .open)
        ].synthesizedMemberwiseInitAccess == .internal)
    }

    @Test("callability matches the compiler's answer per site")
    func callabilityTable() {
        #expect(AccessLevel.private.isCallable(from: .sameFile) == false)
        #expect(AccessLevel.private.isCallable(from: .separateFile) == false)
        #expect(AccessLevel.fileprivate.isCallable(from: .sameFile) == true)
        #expect(AccessLevel.fileprivate.isCallable(from: .separateFile) == false)
        for level in [AccessLevel.internal, .package, .public, .open] {
            #expect(level.isCallable(from: .sameFile) == true)
            #expect(level.isCallable(from: .separateFile) == true)
        }
    }

    @Test("modifier names that aren't about access don't parse as a level")
    func nonAccessModifiersAreIgnored() {
        #expect(AccessLevel(modifierName: "private") == .private)
        #expect(AccessLevel(modifierName: "package") == .package)
        #expect(AccessLevel(modifierName: "static") == nil)
        #expect(AccessLevel(modifierName: "lazy") == nil)
        #expect(AccessLevel(modifierName: "") == nil)
    }
}
