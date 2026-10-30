import Foundation
import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// Two rules that a bigger corpus proved wrong, both fixed here.
///
/// **1. `Sendable` by literal string.** The skip rule looked for `Sendable` in
/// a type's own inheritance clause and documented its blind spot as acceptable:
/// *"an inherited protocol that itself refines Sendable"*. Measured on
/// swift-syntax, that blind spot was the whole library —
/// `public protocol SyntaxProtocol: …, Sendable` with every node declared
/// `: SyntaxProtocol, SyntaxHashable` — and the rule skipped **673 types in one
/// module**, all false positives. A limitation at that scale is the rule not
/// working. `SendableProtocols` now computes the module's refining set as a
/// fixed point; SwiftSyntax's skips fell 673 → 28.
///
/// **2. "No visible stored properties" for a type never declared here.** A
/// whole-module scan reaches types it only ever sees *extended*. Everything
/// member-shaped is then empty and `TypeShape.kind` carries its `.struct`
/// default rather than knowledge, so the diagnostic described a declaration
/// nobody had read — and described enums as structs. Measured on swift-syntax +
/// swift-argument-parser: **435 of the 449 in that bucket had no declaration in
/// the target**, 12 of them enums. The bucket fell 449 → 9.
struct ExtensionOnlyAndSendableTests {

    private func scan(_ files: [String: String]) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawExtOnly-\(UUID().uuidString)/")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var paths: [String] = []
        for (name, contents) in files {
            let path = dir + name
            try? contents.write(toFile: path, atomically: true, encoding: .utf8)
            paths.append(path)
        }
        return ModuleScanner.scan(sourceFiles: paths)
    }

    // MARK: - Sendable through a protocol

    /// The swift-syntax shape, reduced.
    @Test("a type is Sendable through a protocol that refines Sendable")
    func sendableViaProtocol() {
        let map = scan(["S.swift": """
        public protocol NodeProtocol: Sendable {}
        public struct Node: NodeProtocol, Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.isEmpty)
        #expect(map.entries.map(\.typeName).contains("Node"))
    }

    /// Two passes would miss this; the fixed point does not.
    @Test("Sendable is followed through a chain of protocols")
    func sendableThroughChain() {
        let map = scan(["S.swift": """
        public protocol A: Sendable {}
        public protocol B: A {}
        public protocol C: B {}
        public struct Node: C, Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.isEmpty)
    }

    /// The protocol may be declared in a different file of the same target.
    @Test("the refining protocol can live in another file")
    func sendableProtocolAcrossFiles() {
        let map = scan([
            "Proto.swift": "public protocol NodeProtocol: Sendable {}",
            "Node.swift": """
            public struct Node: NodeProtocol, Equatable {
                public let a: Int
            }
            """
        ])
        #expect(map.skippedTypes.isEmpty)
    }

    /// The rule must still fire when nothing supplies `Sendable` — otherwise it
    /// would emit a suite that cannot type-check.
    @Test("a protocol that does not refine Sendable still leaves the type skipped")
    func nonSendableProtocolStillSkips() {
        let map = scan(["S.swift": """
        public protocol Plain {}
        public struct Node: Plain, Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.map(\.reason) == [.notSendable])
    }

    @Test("@unchecked and retroactive spellings are recognized")
    func decoratedSpellings() {
        let map = scan(["S.swift": """
        public struct A: Equatable, @unchecked Sendable { public let a: Int }
        public protocol P: @unchecked Sendable {}
        public struct B: P, Equatable { public let b: Int }
        """])
        #expect(map.skippedTypes.isEmpty)
    }

    // MARK: - Sendable through the standard library

    /// Spelled out rather than read back from
    /// `SendableProtocols.standardLibraryRefinements`, so dropping a name from
    /// that list fails its case here instead of shrinking the test with it.
    @Test(
        "a standard-library protocol that refines Sendable supplies it",
        arguments: [
            "Actor", "Clock", "CodingKey", "DurationProtocol", "Error", "Executor",
            "InstantProtocol", "SerialExecutor", "TaskExecutor", "UnsafeSendable"
        ]
    )
    func standardLibraryRefinementSuppliesSendable(protocolName: String) {
        let map = scan(["S.swift": """
        public struct Node: \(protocolName), Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.isEmpty)
        #expect(map.entries.map(\.typeName).contains("Node"))
    }

    /// Foundation ships no sources, so context files cannot supply these.
    /// Spelled out for the same reason as the standard library's list.
    @Test(
        "a Foundation protocol that refines Sendable supplies it",
        arguments: [
            "CustomNSError", "LocalizedError", "RecoverableError",
            "AttributedStringProtocol", "NotificationCenter.AsyncMessage",
            "SortComparator", "StandardPredicateExpression"
        ]
    )
    func foundationRefinementSuppliesSendable(protocolName: String) {
        let map = scan(["S.swift": """
        import Foundation
        public struct Node: \(protocolName), Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.isEmpty)
        #expect(map.entries.map(\.typeName).contains("Node"))
    }

    /// The Pass 1 shape: `ArgumentParser.ExitCode` reaches `Sendable` only
    /// through `Error`, and was skipped as not `Sendable` before the seeds.
    @Test("a module-local protocol refining Error supplies Sendable")
    func moduleProtocolRefiningError() {
        let map = scan(["S.swift": """
        public protocol AppError: Error {}
        public struct Failure: AppError, Equatable {
            public let code: Int
        }
        """])
        #expect(map.skippedTypes.isEmpty)
    }

    /// Hummingbird declares a type named `Error`, so its conformances say
    /// `Swift.Error`.
    @Test("module-qualified Swift spellings are recognized")
    func qualifiedSpellings() {
        let map = scan(["S.swift": """
        public struct Failure: Swift.Error, Equatable { public let a: Int }
        public struct Point: Equatable, Swift.Sendable { public let b: Int }
        public struct Tick: _Concurrency.Clock, Equatable { public let c: Int }
        public struct Lost: Foundation.LocalizedError, Equatable { public let d: Int }
        """])
        #expect(map.skippedTypes.isEmpty)
    }

    /// At module scope a module's own `Clock` hides the standard library's, so
    /// the seed must not vouch for it.
    @Test("a module's own protocol shadows a standard-library seed")
    func moduleProtocolShadowsSeed() {
        let map = scan(["S.swift": """
        public protocol Clock {}
        public struct Wall: Clock, Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.map(\.reason) == [.notSendable])
    }

    /// And the shadowing protocol is still judged on its own clause.
    @Test("a shadowing protocol that refines Sendable itself still supplies it")
    func shadowingProtocolRefiningSendable() {
        let map = scan(["S.swift": """
        public protocol Clock: Sendable {}
        public struct Wall: Clock, Equatable {
            public let a: Int
        }
        """])
        #expect(map.skippedTypes.isEmpty)
    }

    @Test("an actor is Sendable whatever its inheritance clause says")
    func actorIsSendable() {
        let map = scan(["S.swift": """
        public actor Counter: Hashable {
            public let id: Int
            public static func == (lhs: Counter, rhs: Counter) -> Bool { lhs.id == rhs.id }
            public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
        }
        """])
        #expect(map.skippedTypes.isEmpty)
        #expect(map.entries.map(\.typeName).contains("Counter"))
    }

    // MARK: - Extension-only types

    @Test("a type only extended here is reported as undeclared, not as memberless")
    func extensionOnlyReportsHonestly() {
        let map = scan(["S.swift": "extension SomeForeignType: Equatable {}"])
        guard let entry = map.entries.first(where: { $0.typeName == "SomeForeignType" }),
              case .todo(let reason) = entry.derivationStrategy else {
            Issue.record("expected a .todo entry")
            return
        }
        #expect(reason.contains("only extends the type"))
        #expect(reason.contains("its declaration was not scanned"))
        // The old wording described a body nobody had read.
        #expect(reason.contains("no stored properties visible") == false)
    }

    /// The reason enums showed up in a *struct* bucket: with no declaration the
    /// kind is unknown, and `TypeShape.kind` falls back to `.struct`.
    @Test("the diagnostic makes no claim about the kind")
    func makesNoKindClaim() {
        let map = scan(["S.swift": "extension SomeForeignEnum: Equatable {}"])
        guard let entry = map.entries.first,
              case .todo(let reason) = entry.derivationStrategy else {
            Issue.record("expected a .todo entry")
            return
        }
        #expect(reason.contains("its kind is unknown"))
        #expect(reason.contains("struct") == false)
        #expect(reason.contains("enum") == false)
    }

    /// A struct genuinely declared here with an empty body is a different fact:
    /// it has an `init()` and one value, so it derives, where the extension-only
    /// shape above — empty for want of information — must not.
    @Test("a declared but memberless struct derives, an extended one does not")
    func declaredMemberlessStructDerives() {
        let map = scan(["S.swift": """
        public struct Empty: Equatable, Sendable {}
        extension SomeForeignType: Equatable {}
        """])
        let empty = map.entries.first(where: { $0.typeName == "Empty" })
        #expect(empty?.derivationStrategy == .initializerBased(arguments: []))
        let foreign = map.entries.first(where: { $0.typeName == "SomeForeignType" })
        guard case .todo = foreign?.derivationStrategy else {
            Issue.record("an extension-only type must not derive `SomeForeignType()`")
            return
        }
    }

    @Test("hasPrimaryDeclaration reflects what the scanner saw")
    func flagReflectsReality() {
        let map = scan(["S.swift": """
        public struct Declared: Equatable, Sendable { public let a: Int }
        extension Foreign: Equatable {}
        """])
        #expect(map.shapesByName["Declared"]?.hasPrimaryDeclaration == true)
        #expect(map.shapesByName["Foreign"]?.hasPrimaryDeclaration == false)
    }

    /// Default `true` keeps the macro path — always attached to a declaration —
    /// and every existing caller unchanged.
    @Test("the flag defaults to true for callers that don't set it")
    func defaultsToTrue() {
        let shape = TypeShape(
            name: "T", kind: .struct, inheritedTypes: [], hasUserGen: false
        )
        #expect(shape.hasPrimaryDeclaration)
    }
}
