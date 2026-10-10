import Foundation
import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// **The scanner walked top-level statements only.** A type declared inside
/// another type — or inside an `extension`, which is how swift-collections
/// writes most of its views — was never seen as a primary declaration. It
/// entered the map through `extension BitSet.Counted: …` alone, carrying no
/// stored members, no initializers and no kind, and so stayed `.todo` however
/// derivable it actually was.
///
/// The name was wrong too: `topLevelExtendedTypeName` kept the last component,
/// so the emitted suite said `for: Counted.self` — a name that does not exist
/// at module scope. **Measured 2026-08-08 across swift-collections +
/// swift-numerics + swift-async-algorithms: 13 of the 23 types with an emitted
/// `.todo` generator were nested, and every one was emitted unqualified.**
///
/// So this is a correctness fix before it is a coverage one: the old output for
/// those types could not have compiled even with a hand-written `gen()`.
struct NestedTypeScanningTests {

    private func scan(_ source: String) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawNested-\(UUID().uuidString)/")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "Sample.swift"
        try? source.write(toFile: path, atomically: true, encoding: .utf8)
        return ModuleScanner.scan(sourceFiles: [path])
    }

    // MARK: - Naming

    @Test("a type nested in a type is recorded qualified")
    func nestedInTypeIsQualified() {
        let map = scan("""
        public struct Outer: Sendable {
            public struct Inner: Equatable, Sendable {
                public let a: Int
            }
        }
        """)
        #expect(map.entries.map(\.typeName).contains("Outer.Inner"))
        #expect(map.entries.map(\.typeName).contains("Inner") == false)
    }

    /// The swift-collections shape: `extension BitSet { public struct Counted }`.
    @Test("a type nested in an extension is recorded qualified")
    func nestedInExtensionIsQualified() {
        let map = scan("""
        public struct BitSet: Sendable {}
        extension BitSet {
            public struct Counted: Equatable, Sendable {
                public let a: Int
            }
        }
        """)
        #expect(map.entries.map(\.typeName).contains("BitSet.Counted"))
    }

    /// `extension BitSet.Counted: Hashable` must land on the same key the
    /// primary declaration did, or the conformance is recorded against a
    /// phantom type and the real one loses it.
    @Test("an extension of a nested type joins the nested type's entry")
    func extensionJoinsNestedEntry() {
        let map = scan("""
        public struct BitSet: Sendable {
            public struct Counted: Sendable {
                public let a: Int
            }
        }
        extension BitSet.Counted: Equatable {}
        """)
        let counted = map.entries.filter { $0.typeName == "BitSet.Counted" }
        #expect(counted.count == 1)
        #expect(counted.first?.conformances.contains(.equatable) == true)
    }

    /// Deeper than one level, since nothing about the rule stops at one.
    @Test("nesting composes to arbitrary depth")
    func deepNesting() {
        let map = scan("""
        public struct A: Sendable {
            public struct B: Sendable {
                public struct C: Equatable, Sendable {
                    public let a: Int
                }
            }
        }
        """)
        #expect(map.entries.map(\.typeName).contains("A.B.C"))
    }

    /// A conditional conformance is still skipped as a *conformance* — but its
    /// body is walked, because `extension Foo: P where T: P` says nothing about
    /// the types declared inside it.
    @Test("a conditional conformance's body is still scanned")
    func conditionalExtensionBodyScanned() {
        let map = scan("""
        public struct Box<T>: Sendable {}
        extension Box: Equatable where T: Equatable {
            public struct Tag: Equatable, Sendable {
                public let a: Int
            }
        }
        """)
        #expect(map.entries.map(\.typeName).contains("Box.Tag"))
        // …and the conditional conformance itself is not recorded on Box.
        let box = map.entries.first { $0.typeName == "Box" }
        #expect(box?.conformances.contains(.equatable) != true)
    }

    // MARK: - Emission

    /// A dot is not legal in a Swift identifier, so the qualified name has to
    /// split: qualified in type position, sanitized in identifier position.
    /// Emitting `@Suite struct BitSet.CountedPropertyLawTests` does not parse.
    @Test("the suite and test names are identifiers, the type reference is qualified")
    func emissionSplitsTheTwoPositions() {
        let output = GeneratedFileEmitter.emit(target: "M", map: scan("""
        public struct BitSet: Sendable {
            public struct Counted: Equatable, Sendable {
                public let a: Int
            }
        }
        """))
        #expect(output.contains("@Suite struct BitSet_CountedPropertyLawTests {"))
        #expect(output.contains("@Test func equatable_BitSet_Counted()"))
        #expect(output.contains("for: BitSet.Counted.self"))
        // The invalid spelling must not appear anywhere.
        #expect(output.contains("BitSet.CountedPropertyLawTests") == false)
    }

    /// The generator expression is a type reference too — `Counted(a: …)` would
    /// not resolve.
    @Test("the derived generator constructs through the qualified name")
    func generatorUsesQualifiedName() {
        let output = GeneratedFileEmitter.emit(target: "M", map: scan("""
        public struct BitSet: Sendable {
            public struct Counted: Equatable, Sendable {
                public let a: Int
            }
        }
        """))
        #expect(output.contains(".map { BitSet.Counted(a: $0) }"))
    }

    /// Unqualified names keep their exact previous spelling, so a
    /// `// property-law-suppress: equatable_Foo` marker written before this
    /// change still matches (PRD §5.3 regeneration-as-diff).
    @Test("top-level types are unaffected")
    func topLevelUnchanged() {
        let output = GeneratedFileEmitter.emit(target: "M", map: scan(
            "public struct Foo: Equatable, Sendable { public let a: Int }"
        ))
        #expect(output.contains("@Suite struct FooPropertyLawTests {"))
        #expect(output.contains("@Test func equatable_Foo()"))
        #expect(output.contains("for: Foo.self"))
    }

    @Test("a suppression marker for a nested type round-trips")
    func nestedSuppressionRoundTrips() {
        let map = scan("""
        public struct BitSet: Sendable {
            public struct Counted: Equatable, Sendable {
                public let a: Int
            }
        }
        """)
        let output = GeneratedFileEmitter.emit(
            target: "M", map: map, suppressions: ["equatable_BitSet_Counted"]
        )
        #expect(output.contains("property-law-suppress: equatable_BitSet_Counted"))
        #expect(output.contains("for: BitSet.Counted.self") == false)
    }

    // MARK: - Resolution

    /// The other half of the bargain. Swift resolves `let inner: Inner` inside
    /// `Outer` through lexical scope; a flat universe keyed on `Outer.Inner`
    /// does not, so qualifying the keys would have *cost* this derivation
    /// unless the resolver reads `Outer`'s members from inside `Outer`.
    ///
    /// The scanner derives each entry's strategy itself, so that is the
    /// scanner's job as much as the resolver's: it must pass
    /// `resolve(within: shape.name)`, not `customTypeGenerator`, which reads at
    /// module scope. A leaf index used to hide the difference.
    @Test("an unqualified member reference reaches the nested type")
    func unqualifiedMemberReferenceResolves() {
        let map = scan("""
        public struct Outer: Equatable, Sendable {
            public struct Inner: Equatable, Sendable {
                public let a: Int
            }
            public let inner: Inner
        }
        """)
        guard let outer = map.entries.first(where: { $0.typeName == "Outer" }) else {
            Issue.record("Outer should be emitted")
            return
        }
        guard case .memberwiseArbitrary(let members) = outer.derivationStrategy else {
            Issue.record("Outer should derive through Inner; got \(outer.derivationStrategy)")
            return
        }
        #expect(members.first?.generatorExpression.contains("Outer.Inner(a:") == true)
    }

    /// And the refusal half: `User` is nested in neither `A` nor `B`, so its
    /// `Kind` is not either of theirs — it names a type the scan does not
    /// contain, and Swift would say the same. This once refused because the two
    /// leaves *collided*; it now refuses because neither is in scope, which
    /// is also what declines a single unrelated leaf (the next test).
    @Test("a nested type outside the reference's scope is not reached")
    func outOfScopeNestedTypesRefuse() {
        let map = scan("""
        public struct A: Sendable {
            public struct Kind: Equatable, Sendable { public let a: Int }
        }
        public struct B: Sendable {
            public struct Kind: Equatable, Sendable { public let b: String }
        }
        public struct User: Equatable, Sendable {
            public let kind: Kind
        }
        """)
        guard let user = map.entries.first(where: { $0.typeName == "User" }) else {
            Issue.record("User should be emitted")
            return
        }
        guard case .todo = user.derivationStrategy else {
            Issue.record("expected .todo for an out-of-scope name; got \(user.derivationStrategy)")
            return
        }
    }

    /// SwiftPropertyLaws#63, end to end. `Symbol` here is another module's
    /// type; the only scanned `Symbol` is nested in an unrelated `Document`.
    /// One candidate is still not a match, and building a `Document.Symbol` for
    /// it would emit a call that does not compile.
    @Test("a single unrelated nested namesake is not reached")
    func singleOutOfScopeNamesakeRefuses() {
        let map = scan("""
        public struct Document: Sendable {
            public struct Symbol: Equatable, Sendable { public let id: Int }
        }
        public struct Summary: Equatable, Sendable {
            public let symbol: Symbol
        }
        """)
        guard let summary = map.entries.first(where: { $0.typeName == "Summary" }) else {
            Issue.record("Summary should be emitted")
            return
        }
        guard case .todo = summary.derivationStrategy else {
            Issue.record("expected .todo for another module's Symbol; got \(summary.derivationStrategy)")
            return
        }
    }

    /// A top-level type wins its own leaf — an unqualified `Counted` in source
    /// means the top-level one everywhere except inside the nesting type, so
    /// this is not a collision to arbitrate.
    @Test("a top-level type outranks a nested namesake")
    func topLevelWinsItsLeaf() {
        let map = scan("""
        public struct Counted: Equatable, Sendable { public let top: Int }
        public struct Holder: Sendable {
            public struct Counted: Equatable, Sendable { public let nested: String }
        }
        public struct User: Equatable, Sendable {
            public let counted: Counted
        }
        """)
        guard let user = map.entries.first(where: { $0.typeName == "User" }),
              case .memberwiseArbitrary(let members) = user.derivationStrategy else {
            Issue.record("User should derive through the top-level Counted")
            return
        }
        #expect(members.first?.generatorExpression.contains("Counted(top:") == true)
    }
}
