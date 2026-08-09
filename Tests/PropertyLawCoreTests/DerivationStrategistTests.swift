import Testing
@testable import PropertyLawCore

// One test per priority-order step plus the fall-through cases for each
// strategy — the suite legitimately grows past SwiftLint's default
// type-body-length threshold as derivation strategies ship. Disable is
// paired with an explicit re-enable at end of file.
// swiftlint:disable type_body_length

struct DerivationStrategistTests {

    // MARK: - Strategy A: user-provided gen() wins unconditionally

    @Test func userGenWinsEvenForCaseIterableEnum() {
        // Even a CaseIterable enum yields .userGen when the user supplies
        // gen() — the user's intent always wins.
        let shape = TypeShape(
            name: "Status",
            kind: .enum,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: true
        )
        #expect(DerivationStrategist.strategy(for: shape) == .userGen)
    }

    @Test func userGenWinsForStruct() {
        let shape = TypeShape(
            name: "Foo",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: true
        )
        #expect(DerivationStrategist.strategy(for: shape) == .userGen)
    }

    // MARK: - Strategy B: CaseIterable enums

    @Test func caseIterableEnumDerives() {
        let shape = TypeShape(
            name: "Direction",
            kind: .enum,
            inheritedTypes: ["CaseIterable", "Equatable"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .caseIterable)
    }

    @Test func caseIterableStructDoesNotDeriveAsCaseIterable() {
        // CaseIterable is meaningless on a struct; falls through to .todo.
        let shape = TypeShape(
            name: "Foo",
            kind: .struct,
            inheritedTypes: ["CaseIterable"],
            hasUserGen: false
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for CaseIterable struct")
            return
        }
    }

    // MARK: - Strategy C: RawRepresentable enums

    @Test func intRawEnumDerives() {
        let shape = TypeShape(
            name: "Code",
            kind: .enum,
            inheritedTypes: ["Int", "Equatable"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(.int))
    }

    @Test func stringRawEnumDerives() {
        let shape = TypeShape(
            name: "Status",
            kind: .enum,
            inheritedTypes: ["String", "Codable"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(.string))
    }

    @Test func allRawTypesAreRecognized() {
        for rawType in RawType.allCases {
            let shape = TypeShape(
                name: "Test",
                kind: .enum,
                inheritedTypes: [rawType.rawValue],
                hasUserGen: false
            )
            #expect(DerivationStrategist.strategy(for: shape) == .rawRepresentable(rawType))
        }
    }

    @Test func caseIterableSubsumesRawRepresentable() {
        // When both CaseIterable and a known raw type appear, CaseIterable
        // wins (Strategy B before Strategy C in the priority order — and
        // CaseIterable produces a stronger distribution per PRD §5.7).
        let shape = TypeShape(
            name: "Bits",
            kind: .enum,
            inheritedTypes: ["CaseIterable", "Int"],
            hasUserGen: false
        )
        #expect(DerivationStrategist.strategy(for: shape) == .caseIterable)
    }

    // MARK: - Strategy D: .todo fallback

    @Test func emptyStructFallsThroughToTodo() {
        // `TypeShape.storedMembers` defaults to `[]`. A struct with no
        // visible stored properties has nothing to compose memberwise —
        // strategist falls through to `.todo` with an explanation.
        let shape = TypeShape(
            name: "Coordinate",
            kind: .struct,
            inheritedTypes: ["Equatable", "Hashable"],
            hasUserGen: false
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("Coordinate"))
        #expect(reason.contains("no stored properties"))
    }

    // MARK: - Strategy 3: memberwise-Arbitrary (PRD §5.7)

    @Test func singleMemberStructDerivesMemberwise() {
        let shape = TypeShape(
            name: "ID",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "value", typeName: "Int")]
        )
        let expected: DerivationStrategy = .memberwiseArbitrary(
            members: [MemberSpec(name: "value", rawType: .int)]
        )
        #expect(DerivationStrategist.strategy(for: shape) == expected)
    }

    @Test func multiMemberStructDerivesMemberwise() {
        let shape = TypeShape(
            name: "Coordinate",
            kind: .struct,
            inheritedTypes: ["Equatable", "Hashable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "easting", typeName: "Int"),
                StoredMember(name: "northing", typeName: "Int")
            ]
        )
        let expected: DerivationStrategy = .memberwiseArbitrary(members: [
            MemberSpec(name: "easting", rawType: .int),
            MemberSpec(name: "northing", rawType: .int)
        ])
        #expect(DerivationStrategist.strategy(for: shape) == expected)
    }

    @Test func structBeyondTenMembersStillDerivesMemberwise() {
        // 11 members — over the flat zip-10 limit. Nested composition means the
        // strategist derives it instead of falling to .todo (the confident zero
        // the app road-test hit on ordinary 11–14-member value types).
        let shape = TypeShape(
            name: "Wide",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: (0..<11).map { StoredMember(name: "m\($0)", typeName: "Int") }
        )
        let expected: DerivationStrategy = .memberwiseArbitrary(
            members: (0..<11).map { MemberSpec(name: "m\($0)", rawType: .int) }
        )
        #expect(DerivationStrategist.strategy(for: shape) == expected)
    }

    @Test func mixedRawTypeStructDerivesMemberwise() {
        let shape = TypeShape(
            name: "Record",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "id", typeName: "Int"),
                StoredMember(name: "label", typeName: "String"),
                StoredMember(name: "active", typeName: "Bool")
            ]
        )
        let expected: DerivationStrategy = .memberwiseArbitrary(members: [
            MemberSpec(name: "id", rawType: .int),
            MemberSpec(name: "label", rawType: .string),
            MemberSpec(name: "active", rawType: .bool)
        ])
        #expect(DerivationStrategist.strategy(for: shape) == expected)
    }

    @Test func structWithUnknownTypeFallsThrough() {
        // `Widget` is a bespoke domain type with no recognized raw / known
        // value generator, so memberwise derivation falls through to .todo.
        let shape = TypeShape(
            name: "Doc",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "widget", typeName: "Widget")]
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("Widget"))
        #expect(reason.contains("no recognized stdlib raw type"))
    }

    @Test func structWithUserInitFallsThrough() {
        // Swift suppresses the synthesized memberwise init when the type
        // declares any user `init(...)` — strategist must fall through.
        let shape = TypeShape(
            name: "Wrapped",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "value", typeName: "Int")],
            hasUserInit: true
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo when user init suppresses synthesis")
            return
        }
        #expect(reason.contains("user `init"))
    }

    @Test func structBeyondTheNestedCeilingFallsThrough() {
        // 101 members exceeds memberwiseMemberLimit (100) — the outer zip of
        // groups would itself bust the 10-arity cap. Nested composition raised
        // the wall from 10 to 100; past that it still declines, with a reason.
        let members = (0..<101).map { idx in
            StoredMember(name: "m\(idx)", typeName: "Int")
        }
        let shape = TypeShape(
            name: "Absurd",
            kind: .struct,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: members
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo at 101 members")
            return
        }
        #expect(reason.contains("101"))
        #expect(reason.contains("nested"))
    }

    @Test func classWithRawMembersFallsThroughMemberwise() {
        // Classes are intentionally excluded from memberwise derivation —
        // reference-semantic init contracts complicate the synthesized-init
        // story enough that v1 punts.
        let shape = TypeShape(
            name: "Box",
            kind: .class,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "value", typeName: "Int")]
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for class kind")
            return
        }
        #expect(reason.contains("structs only"))
    }

    @Test func actorWithRawMembersFallsThroughMemberwise() {
        let shape = TypeShape(
            name: "Counter",
            kind: .actor,
            inheritedTypes: [],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "value", typeName: "Int")]
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for actor kind")
            return
        }
    }

    @Test func userGenWinsOverMemberwise() {
        let shape = TypeShape(
            name: "ID",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: true,
            storedMembers: [StoredMember(name: "value", typeName: "Int")]
        )
        #expect(DerivationStrategist.strategy(for: shape) == .userGen)
    }

    /// **This test's comment and its fixture disagreed, and the old diagnostic
    /// hid it.** The comment said "associated-value enum"; the shape carries no
    /// `enumCases` at all, which is a *caseless* enum — an uninhabited type. The
    /// single catch-all reason ("not `CaseIterable` … or add `: CaseIterable`")
    /// was emitted for both, so the assertion passed either way and the
    /// mismatch was invisible.
    ///
    /// It now asserts what the fixture actually is. The associated-value case
    /// it meant to cover lives in `EnumTodoReasonTests.unresolvablePayload`.
    @Test func caselessEnumFallsThroughToTodo() {
        let shape = TypeShape(
            name: "Either",
            kind: .enum,
            inheritedTypes: ["Equatable"],
            hasUserGen: false
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("Either"))
        #expect(reason.contains("declares no cases"))
        // `: CaseIterable` cannot rescue an uninhabited type — `allCases` would
        // be empty and the generator would never yield.
        #expect(reason.contains("CaseIterable") == false)
    }

    @Test func unknownRawTypeFallsThroughToTodo() {
        // CustomRawType isn't in our RawType allCases — strategist
        // doesn't try to derive against arbitrary user types.
        let shape = TypeShape(
            name: "Foo",
            kind: .enum,
            inheritedTypes: ["CustomRawType", "Equatable"],
            hasUserGen: false
        )
        guard case .todo = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return
        }
    }

    // MARK: - RawType generator expressions

    @Test func intGeneratorExpressionMatchesUpstream() {
        #expect(RawType.int.generatorExpression == "Gen<Int>.int()")
    }

    @Test func boolGeneratorExpressionMatchesUpstream() {
        #expect(RawType.bool.generatorExpression == "Gen<Bool>.bool()")
    }

    @Test func stringGeneratorExpressionMatchesUpstream() {
        #expect(RawType.string.generatorExpression == "Gen<Character>.letterOrNumber.string(of: 0...8)")
    }

    @Test func fixedWidthIntGeneratorsUseTypedFactoryName() {
        // swift-property-based names them int8/int16/... not int(in:) on
        // the typed extensions.
        #expect(RawType.int8.generatorExpression == "Gen<Int8>.int8()")
        #expect(RawType.uint64.generatorExpression == "Gen<UInt64>.uint64()")
    }
}

// swiftlint:enable type_body_length
