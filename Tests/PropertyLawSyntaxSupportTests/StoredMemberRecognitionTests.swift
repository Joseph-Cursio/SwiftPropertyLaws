import PropertyLawCore
import SwiftParser
import SwiftSyntax
import Testing
@testable import PropertyLawSyntaxSupport

/// Which bindings `MemberBlockInspector` counts as stored. The synthesized
/// memberwise initializer takes every stored property, so a stored property
/// missing from the shape makes a derived `Type(…)` call omit an argument —
/// and an empty shape reads as a stateless type constructible with `Type()`.
struct StoredMemberRecognitionTests {

    private func members(_ source: String) throws -> [StoredMember] {
        let file = Parser.parse(source: source)
        let structDecl = try #require(
            file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        )
        return MemberBlockInspector.storedMembers(in: structDecl.memberBlock)
    }

    @Test("an observed property is stored")
    func observedPropertyIsStored() throws {
        let parsed = try members("""
        struct S {
            var count: Int { didSet { print(count) } }
            var label: String = "" { willSet { } didSet { } }
        }
        """)
        #expect(parsed.map(\.name) == ["count", "label"])
        #expect(parsed.map(\.typeName) == ["Int", "String"])
    }

    @Test("computed properties are still skipped")
    func computedPropertiesAreSkipped() throws {
        let parsed = try members("""
        struct S {
            var bare: Int { 1 }
            var getter: Int { get { 1 } }
            var both: Int { get { 1 } set { } }
            let stored: Int
        }
        """)
        #expect(parsed.map(\.name) == ["stored"])
    }

    @Test("a tuple pattern records one member per element")
    func tuplePatternIsSplit() throws {
        let parsed = try members("""
        struct S {
            let (x, y): (Int, String)
            var (a, (b, c)): (Bool, (Int8, Int16))
        }
        """)
        #expect(parsed.map(\.name) == ["x", "y", "a", "b", "c"])
        #expect(parsed.map(\.typeName) == ["Int", "String", "Bool", "Int8", "Int16"])
    }

    @Test("a tuple pattern that does not line up with its type records nothing guessed")
    func mismatchedTuplePatternIsNotGuessed() throws {
        let parsed = try members("""
        struct S {
            let (x, _): (Int, String)
            let (p, q): (Int, String, Bool)
        }
        """)
        #expect(parsed.map(\.name) == ["x"])
    }
}
