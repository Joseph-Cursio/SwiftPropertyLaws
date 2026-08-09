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

    /// A struct genuinely declared here with an empty body is a different fact
    /// and keeps the original message.
    @Test("a declared but memberless struct keeps its own diagnostic")
    func declaredMemberlessStructUnchanged() {
        let map = scan(["S.swift": "public struct Empty: Equatable, Sendable {}"])
        guard let entry = map.entries.first(where: { $0.typeName == "Empty" }),
              case .todo(let reason) = entry.derivationStrategy else {
            Issue.record("expected a .todo entry")
            return
        }
        #expect(reason.contains("no stored properties visible"))
        #expect(reason.contains("only extends the type") == false)
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
