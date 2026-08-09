import PropertyLawCore
import SwiftParser
import SwiftSyntax
import Testing
@testable import PropertyLawSyntaxSupport

/// `MemberBlockInspector` is where the access level enters the pipeline. The
/// strategist's rule is only as sound as this reading, and the reading has one
/// trap: `private(set)` spells `private` while restricting nothing the
/// synthesized memberwise initializer depends on.
struct StoredMemberAccessLevelTests {

    /// Parses a struct declaration and returns its stored members as the macro
    /// and the discovery plugin both see them.
    private func members(_ source: String) throws -> [StoredMember] {
        let file = Parser.parse(source: source)
        let structDecl = try #require(
            file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        )
        return MemberBlockInspector.storedMembers(in: structDecl.memberBlock)
    }

    @Test("each access modifier is read off the declaration")
    func modifiersAreRead() throws {
        let parsed = try members("""
        struct S {
            private let a: Int
            fileprivate let b: Int
            internal let c: Int
            package let d: Int
            public let e: Int
            let f: Int
        }
        """)
        #expect(parsed.map(\.name) == ["a", "b", "c", "d", "e", "f"])
        #expect(parsed.map(\.accessLevel) == [
            .private, .fileprivate, .internal, .package, .public, .internal
        ])
    }

    /// The false-positive guard. `private(set) var b: Int` leaves the
    /// memberwise initializer `internal` — confirmed with a two-file
    /// `swiftc -typecheck` on 2026-08-08, where the cross-file call compiled.
    /// Reading `modifier.name.text` without checking `detail` would report
    /// `.private` here and decline a derivable type.
    @Test("private(set) and fileprivate(set) are not access restrictions")
    func setterOnlyModifiersAreNotRestrictions() throws {
        let parsed = try members("""
        struct S {
            private(set) var a: Int
            fileprivate(set) var b: Int
        }
        """)
        #expect(parsed.map(\.accessLevel) == [.internal, .internal])
    }

    /// A getter-restricting modifier alongside a setter-restricting one still
    /// restricts: `public private(set)` is a `public` property.
    @Test("a paired getter modifier is still read")
    func pairedModifierIsRead() throws {
        let parsed = try members("""
        struct S {
            public private(set) var a: Int
        }
        """)
        #expect(parsed.map(\.accessLevel) == [.public])
    }

    /// Access sits alongside modifiers that have nothing to do with it.
    @Test("non-access modifiers don't disturb the reading")
    func nonAccessModifiersIgnored() throws {
        let parsed = try members("""
        struct S {
            private lazy var a: Int = 0
            weak var b: AnyObject?
        }
        """)
        #expect(parsed.map(\.accessLevel) == [.private, .internal])
    }

    /// The initializer reader shares `accessLevel(of:)` with the stored-property
    /// one, so a `private init` is recognised by the same rule that recognises
    /// a `private let`.
    @Test("initializer access levels are read")
    func initializerAccessIsRead() throws {
        let file = Parser.parse(source: """
        struct S {
            private init(a: Int) {}
            fileprivate init(b: Int) {}
            init(c: Int) {}
            public init(d: Int) {}
        }
        """)
        let structDecl = try #require(
            file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.first
        )
        let inits = MemberBlockInspector.initializers(in: structDecl.memberBlock)
        #expect(inits.map(\.accessLevel) == [.private, .fileprivate, .internal, .public])
    }

    /// Multi-binding lines share one modifier list, so both bindings inherit it.
    @Test("a multi-binding declaration applies its modifier to every binding")
    func multiBindingSharesAccess() throws {
        let parsed = try members("""
        struct S {
            private let a: Int, b: Int
        }
        """)
        #expect(parsed.map(\.name) == ["a", "b"])
        #expect(parsed.map(\.accessLevel) == [.private, .private])
    }
}
