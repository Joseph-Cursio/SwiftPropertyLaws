import Foundation
import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// A per-target scan reaches types it can only see *extended*.
/// `AccessorBlockSyntax` is declared in `SwiftSyntax` and extended in
/// `SwiftParser`, so scanning `SwiftParser` alone knows nothing about it — no
/// members, no initializers, not even its kind.
///
/// **Measured on swift-syntax: 114 of `SwiftParser`'s 199 detected types had no
/// declaration in the target. With its dependencies handed in as context, 9.**
/// Derived generators over the same run went 1 → 6.
///
/// Merging the two lists would be the wrong fix — it also emits a suite for
/// every dependency type, so `SwiftParser`'s file would carry 842 suites
/// instead of 199 and duplicate everything `SwiftSyntax`'s own run emits.
/// Context is for *knowing*, not for testing, and these tests pin that line.
struct ContextFileTests {

    private func scan(target: [String: String], context: [String: String] = [:]) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawCtx-\(UUID().uuidString)/")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        func write(_ files: [String: String], _ prefix: String) -> [String] {
            files.map { name, contents in
                let path = dir + prefix + name
                try? contents.write(toFile: path, atomically: true, encoding: .utf8)
                return path
            }
        }
        let targetPaths = write(target, "t_")
        let contextPaths = write(context, "c_")
        return ModuleScanner.scan(sourceFiles: targetPaths, contextFiles: contextPaths)
    }

    private let foreignDeclaration = """
    public struct Foreign: Sendable {
        public let a: Int
        public let b: String
    }
    """

    // MARK: - Context supplies the declaration

    @Test("without context, an extended type has no declaration and says so")
    func withoutContext() {
        let map = scan(target: ["E.swift": "extension Foreign: Equatable {}"])
        guard case .todo(let reason) = map.entries.first?.derivationStrategy else {
            Issue.record("expected .todo")
            return
        }
        #expect(reason.contains("only extends the type"))
    }

    @Test("with context, the same type derives")
    func withContext() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: ["F.swift": foreignDeclaration]
        )
        guard let entry = map.entries.first(where: { $0.typeName == "Foreign" }) else {
            Issue.record("Foreign should still be an entry — this target adds the conformance")
            return
        }
        guard case .memberwiseArbitrary = entry.derivationStrategy else {
            Issue.record("expected derivation from the context declaration; got \(entry.derivationStrategy)")
            return
        }
    }

    @Test("context makes hasPrimaryDeclaration true")
    func contextSuppliesTheFlag() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: ["F.swift": foreignDeclaration]
        )
        #expect(map.shapesByName["Foreign"]?.hasPrimaryDeclaration == true)
        #expect(map.shapesByName["Foreign"]?.kind == .struct)
    }

    // MARK: - Context never emits

    /// The whole point of the split. A dependency type nobody in this target
    /// mentions is not this target's to test.
    @Test("a context-only type gets no suite")
    func contextOnlyTypeIsNotAnEntry() {
        let map = scan(
            target: ["T.swift": "public struct Mine: Equatable, Sendable { public let a: Int }"],
            context: ["F.swift": "public struct Theirs: Equatable, Sendable { public let a: Int }"]
        )
        #expect(map.entries.map(\.typeName) == ["Mine"])
        let output = GeneratedFileEmitter.emit(target: "M", map: map)
        #expect(output.contains("TheirsPropertyLawTests") == false)
    }

    /// …nor is it reported as skipped. It was never a candidate.
    @Test("a context-only type is not reported as skipped either")
    func contextOnlyTypeIsNotSkipped() {
        let map = scan(
            target: ["T.swift": "public struct Mine: Equatable, Sendable { public let a: Int }"],
            // Both a private type and a non-Sendable public one — either would
            // be reported if context types were candidates.
            context: [
                "F.swift": """
                private struct Hidden: Equatable { let a: Int }
                public struct Bare: Equatable { public let a: Int }
                """
            ]
        )
        #expect(map.skippedTypes.isEmpty)
    }

    /// A context type still joins the resolver universe — that is what lets a
    /// target type with a foreign member derive.
    @Test("a context type resolves as a target type's member")
    func contextTypeResolvesAsMember() {
        let map = scan(
            target: ["T.swift": """
            public struct Mine: Equatable, Sendable {
                public let foreign: Foreign
            }
            """],
            context: ["F.swift": foreignDeclaration]
        )
        guard let mine = map.entries.first(where: { $0.typeName == "Mine" }),
              case .memberwiseArbitrary(let members) = mine.derivationStrategy else {
            Issue.record("Mine should derive through the context declaration of Foreign")
            return
        }
        #expect(members.first?.generatorExpression.contains("Foreign(a:") == true)
    }

    /// A `Sendable`-refining protocol declared in a dependency has to count, or
    /// the skip rule reintroduces the false positives it was fixed for.
    @Test("a Sendable-refining protocol from context counts")
    func sendableProtocolFromContext() {
        let map = scan(
            target: ["T.swift": "public struct Node: NodeProtocol, Equatable { public let a: Int }"],
            context: ["P.swift": "public protocol NodeProtocol: Sendable {}"]
        )
        #expect(map.skippedTypes.isEmpty)
        #expect(map.entries.map(\.typeName).contains("Node"))
    }

    // MARK: - Ordering and back-compat

    /// A name declared on both sides is a different module's same-named type.
    /// The target's declaration is the only one recorded: the context's is
    /// hidden (`ModuleScanner.typesDeclared(in:)`), so this no longer rests on
    /// context being walked first. The namesake tests below pin the rest.
    @Test("a name declared in both takes the target's declaration")
    func targetDeclarationWins() {
        let map = scan(
            target: ["T.swift": """
            public struct Foreign: Equatable, Sendable {
                public let mine: Int
            }
            """],
            context: ["F.swift": """
            public struct Foreign: Sendable {
                public let theirs: String
            }
            """]
        )
        guard let foreign = map.entries.first(where: { $0.typeName == "Foreign" }),
              case .memberwiseArbitrary(let members) = foreign.derivationStrategy else {
            Issue.record("expected Foreign to derive")
            return
        }
        #expect(members.map(\.name) == ["mine"])
        #expect(foreign.conformances.contains(.equatable))
    }

    // MARK: - A dependency's namesake

    /// The PRD §8 Pass 1 shape. Sitrep declares its own `Node`, and its
    /// dependency Yams declares an unrelated `Node` that is `Hashable` and
    /// `Comparable`. Inside the target the name means the target's type, so
    /// none of the dependency's conformances or provenance belong to it.
    @Test("a dependency's namesake lends the target type nothing")
    func namesakeLendsNoConformances() {
        let map = scan(
            target: ["T.swift": """
            public struct Node: Equatable, Sendable {
                public let name: String
            }
            """],
            context: ["Yams.swift": """
            public enum Node: Hashable, Comparable, Sendable {
                case scalar(String)
                public static func < (lhs: Node, rhs: Node) -> Bool { false }
            }
            extension Node: CustomStringConvertible {
                public var description: String { "" }
            }
            """]
        )
        guard let node = map.entries.first(where: { $0.typeName == "Node" }) else {
            Issue.record("Node should be an entry")
            return
        }
        #expect(node.conformances == [.equatable])
        #expect(node.provenances.map(\.filePath).allSatisfy { !$0.contains("/c_") })
    }

    /// Members used to survive only by walk order, and only when the target's
    /// list was non-empty: the last *non-empty* list won, so a memberless target
    /// type took its namesake's members and derived `Token(raw:)`, which does
    /// not exist.
    @Test("a memberless target type does not take its namesake's members")
    func memberlessTargetKeepsItsOwnShape() {
        let map = scan(
            target: ["T.swift": "public struct Token: Equatable, Sendable {}"],
            context: ["F.swift": """
            public struct Token: Sendable {
                public let raw: String
            }
            """]
        )
        #expect(map.shapesByName["Token"]?.storedMembers.isEmpty == true)
        guard case .initializerBased(let arguments) = map.entries
            .first(where: { $0.typeName == "Token" })?.derivationStrategy else {
            Issue.record("expected the stateless `Token()` derivation")
            return
        }
        #expect(arguments.isEmpty)
    }

    /// `Node.Scalar` in the dependency belongs to the dependency's `Node`,
    /// whether it is declared inside it, inside an extension of it, or
    /// extended by its dotted name.
    @Test("types nested in a hidden namesake are hidden with it")
    func nestedInNamesakeIsHidden() {
        let map = scan(
            target: ["T.swift": "public struct Node: Equatable, Sendable { public let a: Int }"],
            context: ["Yams.swift": """
            public enum Node: Hashable, Sendable {
                case scalar
                public struct Scalar: Hashable, Sendable { public let value: String }
            }
            extension Node {
                public struct Mapping: Hashable, Sendable { public let count: Int }
            }
            extension Node.Sequence: CustomStringConvertible {
                public var description: String { "" }
            }
            """]
        )
        #expect(map.shapesByName["Node.Scalar"] == nil)
        #expect(map.shapesByName["Node.Mapping"] == nil)
        #expect(map.shapesByName["Node.Sequence"] == nil)
    }

    /// A typealias names a type too. Left in, the dependency's `Node = String`
    /// would resolve a target member typed `Node` as a `String`.
    @Test("a dependency's typealias of a target type's name is hidden")
    func namesakeAliasIsHidden() {
        let map = scan(
            target: ["T.swift": "public struct Node: Equatable, Sendable { public let a: Int }"],
            context: ["F.swift": "public typealias Node = String"]
        )
        #expect(map.aliases["Node"] == nil)
    }

    /// Hiding is by qualified name. The target's `Outer.Node` says nothing
    /// about a top-level `Node`, which here is the dependency's type the target
    /// extends, so its declaration must still arrive.
    @Test("a namesake nested elsewhere in the target hides nothing")
    func nestedTargetTypeHidesNoTopLevelNamesake() {
        let map = scan(
            target: ["T.swift": """
            public struct Outer: Equatable, Sendable {
                public struct Node: Equatable, Sendable { public let a: Int }
                public let a: Int
            }
            extension Node: CustomStringConvertible {
                public var description: String { "" }
            }
            """],
            context: ["F.swift": """
            public struct Node: Hashable, Sendable {
                public let b: String
            }
            """]
        )
        guard let node = map.entries.first(where: { $0.typeName == "Node" }) else {
            Issue.record("the extended dependency type should be an entry")
            return
        }
        #expect(node.conformances.contains(.hashable))
        #expect(map.entries.contains { $0.typeName == "Outer.Node" })
    }

    /// Omitting context reproduces the previous behaviour exactly.
    @Test("no context files means no behaviour change")
    func emptyContextIsUnchanged() {
        let source = ["T.swift": "public struct Mine: Equatable, Sendable { public let a: Int }"]
        let withEmpty = scan(target: source, context: [:])
        #expect(withEmpty.entries.map(\.typeName) == ["Mine"])
        guard case .memberwiseArbitrary = withEmpty.entries.first?.derivationStrategy else {
            Issue.record("expected the ordinary derivation")
            return
        }
    }
}
