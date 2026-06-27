import Testing
@testable import PropertyLawCore

/// Tier 1 of the generator-derivation strengthening (Idea #3): members
/// typed as optionals, arrays, sets, and dictionaries of recognized raw
/// types now compose `swift-property-based` combinators instead of falling
/// through to `.todo`. These tests pin the parser
/// (`DerivationStrategist.memberGenerator`) directly, then confirm the
/// strategy + emitter paths thread the composed expression end-to-end.
struct CompositeMemberDerivationTests {

    // MARK: - Optionals

    @Test func optionalSugarComposesDotOptional() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Int?")
                == "Gen<Int>.int().optional"
        )
    }

    @Test func optionalStringLiftsThroughStringGenerator() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "String?")
                == "Gen<Character>.letterOrNumber.string(of: 0...8).optional"
        )
    }

    @Test func explicitOptionalGenericMatchesSugar() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Optional<Int>")
                == "Gen<Int>.int().optional"
        )
    }

    @Test func doubleOptionalNestsTwice() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Int??")
                == "Gen<Int>.int().optional.optional"
        )
    }

    // MARK: - Arrays

    @Test func arraySugarComposesDotArray() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[Int]")
                == "Gen<Int>.int().array(of: 0...8)"
        )
    }

    @Test func arrayGenericMatchesSugar() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Array<Int>")
                == "Gen<Int>.int().array(of: 0...8)"
        )
    }

    @Test func arrayOfOptionalNestsElementFirst() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[Int?]")
                == "Gen<Int>.int().optional.array(of: 0...8)"
        )
    }

    @Test func optionalArrayWrapsArrayOnOutside() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[Int]?")
                == "Gen<Int>.int().array(of: 0...8).optional"
        )
    }

    // MARK: - Sets

    @Test func setComposesDotSet() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Set<Int>")
                == "Gen<Int>.int().set(ofAtMost: 0...8)"
        )
    }

    @Test func optionalSetWrapsSetOnOutside() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Set<Int>?")
                == "Gen<Int>.int().set(ofAtMost: 0...8).optional"
        )
    }

    // MARK: - Dictionaries

    @Test func dictionarySugarZipsKeyAndValue() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[String: Int]")
                == "zip(Gen<Character>.letterOrNumber.string(of: 0...8), "
                + "Gen<Int>.int()).dictionary(ofAtMost: 0...8)"
        )
    }

    @Test func dictionaryGenericMatchesSugar() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Dictionary<String, Int>")
                == "zip(Gen<Character>.letterOrNumber.string(of: 0...8), "
                + "Gen<Int>.int()).dictionary(ofAtMost: 0...8)"
        )
    }

    @Test func nestedDictionaryValueSplitsAtTopLevelColonOnly() {
        // The inner `[Int: Int]` colon must not be mistaken for the outer
        // separator — the depth-aware scanner splits at the outer colon.
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[String: [Int]]")
                == "zip(Gen<Character>.letterOrNumber.string(of: 0...8), "
                + "Gen<Int>.int().array(of: 0...8)).dictionary(ofAtMost: 0...8)"
        )
    }

    // MARK: - Unsupported (still nil → .todo at the strategy level)

    @Test func customElementTypeIsUnresolved() {
        #expect(DerivationStrategist.memberGenerator(forTypeName: "URL") == nil)
        #expect(DerivationStrategist.memberGenerator(forTypeName: "[CustomType]") == nil)
        #expect(DerivationStrategist.memberGenerator(forTypeName: "[String: CustomType]") == nil)
    }

    @Test func customTypeWithSetPrefixIsNotMistakenForSet() {
        // `Setting` must not parse as `Set<...>`.
        #expect(DerivationStrategist.memberGenerator(forTypeName: "Setting") == nil)
    }

    // MARK: - Strategy-level end-to-end

    @Test func structWithCompositeMembersDerivesMemberwise() {
        let shape = TypeShape(
            name: "Cart",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "tags", typeName: "[String]"),
                StoredMember(name: "count", typeName: "Int")
            ]
        )
        let expected: DerivationStrategy = .memberwiseArbitrary(members: [
            MemberSpec(
                name: "tags",
                generatorExpression: "Gen<Character>.letterOrNumber.string(of: 0...8).array(of: 0...8)"
            ),
            MemberSpec(name: "count", rawType: .int)
        ])
        #expect(DerivationStrategist.strategy(for: shape) == expected)
    }

    @Test func structWithUnresolvedCompositeMemberFallsThroughToTodo() {
        let shape = TypeShape(
            name: "Doc",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "links", typeName: "[URL]")]
        )
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo for unresolved composite member")
            return
        }
        #expect(reason.contains("[URL]"))
        #expect(reason.contains("no recognized stdlib raw type"))
    }

    // MARK: - Emitter end-to-end

    @Test func singleCompositeMemberEmitsComposedGenerator() {
        let expr = MemberwiseEmitter.expression(
            typeName: "Bag",
            members: [
                MemberSpec(
                    name: "items",
                    generatorExpression: "Gen<Int>.int().array(of: 0...8)"
                )
            ]
        )
        #expect(expr == "Gen<Int>.int().array(of: 0...8).map { Bag(items: $0) }")
    }

    @Test func mixedRawAndCompositeMembersZip() {
        let expr = MemberwiseEmitter.expression(
            typeName: "Order",
            members: [
                MemberSpec(name: "id", rawType: .int),
                MemberSpec(
                    name: "skus",
                    generatorExpression: "Gen<Character>.letterOrNumber.string(of: 0...8).array(of: 0...8)"
                )
            ]
        )
        let expected = """
            zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0...8).array(of: 0...8))
                        .map { Order(id: $0.0, skus: $0.1) }
            """
        #expect(expr == expected)
    }
}
