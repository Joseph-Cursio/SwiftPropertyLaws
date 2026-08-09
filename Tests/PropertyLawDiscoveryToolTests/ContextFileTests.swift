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

    /// **Context is walked first, and that ordering is load-bearing** when a
    /// name is declared on both sides — a different module's same-named type.
    /// `record` lets the last non-empty member list win, so target-last means
    /// the target's own declaration is the one that survives. Reversing the two
    /// lists generates the *context* type's shape under the target's name.
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
