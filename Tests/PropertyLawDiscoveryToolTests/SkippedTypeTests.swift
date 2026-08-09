import Foundation
import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// Two reasons a detected type gets no suite, both of which mean the emitted
/// code would not compile:
///
/// 1. **Not nameable.** `@testable import` promotes `internal`; it does nothing
///    for `private` / `fileprivate`, whose visibility is scoped to a
///    declaration or a file rather than a module. The suite could not write
///    `for: Thing.self`.
/// 2. **Not `Sendable`.** Swift infers `Sendable` for non-public types only,
///    and every `check…PropertyLaws` entry point constrains its value to
///    `Sendable`. This one was invisible until `@testable import` landed —
///    while the generated file named no types at all, nothing reached the point
///    of being rejected for it.
///
/// Dropping silently would be the wrong half of either fix: a type that
/// vanishes from a generated file with no note reads as "nothing to test here".
/// These pin both halves — the suite is gone *and* the reason is stated.
struct SkippedTypeTests {

    private func scan(_ source: String) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawAccess-\(UUID().uuidString)/")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "Sample.swift"
        try? source.write(toFile: path, atomically: true, encoding: .utf8)
        return ModuleScanner.scan(sourceFiles: [path])
    }

    private let sample = """
    public struct PublicThing: Equatable, Sendable {
        public let a: Int
    }

    struct InternalThing: Equatable {
        let a: Int
    }

    private struct PrivateThing: Equatable {
        let a: Int
    }

    fileprivate struct FileprivateThing: Equatable {
        let a: Int
    }
    """

    // MARK: - Access level

    @Test("internal types survive — @testable is what makes that sound")
    func internalTypesSurvive() {
        let names = scan(sample).entries.map(\.typeName)
        #expect(names.contains("InternalThing"))
        #expect(names.contains("PublicThing"))
    }

    @Test("private and fileprivate types get no suite")
    func restrictedTypesDropped() {
        let names = scan(sample).entries.map(\.typeName)
        #expect(names.contains("PrivateThing") == false)
        #expect(names.contains("FileprivateThing") == false)
    }

    @Test("dropped types are reported with their level, sorted")
    func droppedTypesReported() {
        let skipped = scan(sample).skippedTypes
        #expect(skipped.map(\.typeName) == ["FileprivateThing", "PrivateThing"])
        #expect(skipped.map(\.reason) == [.notNameable(.fileprivate), .notNameable(.private)])
    }

    /// A type declared elsewhere and seen only through `extension Foo: Equatable`
    /// has no primary decl to read a level from. Treating that `.implicit` as a
    /// restriction would drop every cross-module conformance the plugin exists
    /// to find.
    @Test("extension-only types are kept")
    func extensionOnlyTypesKept() {
        let map = scan("extension SomeExternalType: Equatable {}")
        #expect(map.entries.map(\.typeName) == ["SomeExternalType"])
        #expect(map.skippedTypes.isEmpty)
    }

    /// A `private` helper is still a fine member type for a public type's
    /// generator. Dropping it from the resolver universe rather than only from
    /// the emitted suites would cost derivations that compile fine.
    @Test("a skipped type still resolves as another type's member")
    func skippedTypeStillResolvesAsMember() {
        let map = scan("""
        private struct Inner: Equatable {
            let a: Int
        }

        public struct Outer: Equatable, Sendable {
            public let inner: Inner
        }
        """)
        #expect(map.skippedTypes.map(\.typeName) == ["Inner"])
        guard let outer = map.entries.first(where: { $0.typeName == "Outer" }) else {
            Issue.record("Outer should still be emitted")
            return
        }
        guard case .memberwiseArbitrary = outer.derivationStrategy else {
            Issue.record("Outer should derive through Inner; got \(outer.derivationStrategy)")
            return
        }
    }

    // MARK: - Sendable

    /// Measured against the compiler on 2026-08-08: `checkHashablePropertyLaws`
    /// on a `public struct Point: Hashable` in another module reports *"type
    /// 'PublicPoint' does not conform to the 'Sendable' protocol"*.
    @Test("a public type without Sendable gets no suite")
    func publicNonSendableSkipped() {
        let map = scan("public struct Bare: Equatable { public let a: Int }")
        #expect(map.entries.isEmpty)
        #expect(map.skippedTypes.map(\.reason) == [.notSendable])
    }

    @Test("an explicit Sendable conformance keeps the suite")
    func explicitSendableKept() {
        let map = scan("public struct Fine: Equatable, Sendable { public let a: Int }")
        #expect(map.entries.map(\.typeName) == ["Fine"])
        #expect(map.skippedTypes.isEmpty)
    }

    /// The scanner aggregates extension inheritance clauses, so a retroactive
    /// conformance in the same module counts.
    @Test("Sendable via a retroactive extension keeps the suite")
    func extensionSendableKept() {
        let map = scan("""
        public struct Retro: Equatable { public let a: Int }
        extension Retro: Sendable {}
        """)
        #expect(map.entries.map(\.typeName) == ["Retro"])
        #expect(map.skippedTypes.isEmpty)
    }

    /// `@unchecked Sendable` satisfies the constraint, and appears in the
    /// inheritance clause verbatim — the substring match is deliberate.
    @Test("@unchecked Sendable keeps the suite")
    func uncheckedSendableKept() {
        let map = scan("public struct Unchecked: Equatable, @unchecked Sendable { public let a: Int }")
        #expect(map.entries.map(\.typeName) == ["Unchecked"])
        #expect(map.skippedTypes.isEmpty)
    }

    /// Verified against the compiler on 2026-08-08 with a two-target package:
    /// `package` types *are* implicitly `Sendable` across modules, so the rule
    /// must stop at `public` / `open`. Applying it to `package` would drop
    /// derivable types.
    @Test("package and internal types need no explicit Sendable")
    func nonPublicNeedsNoSendable() {
        let map = scan("""
        package struct Pkg: Equatable { package let a: Int }
        struct Int1: Equatable { let a: Int }
        """)
        #expect(map.entries.map(\.typeName) == ["Int1", "Pkg"])
        #expect(map.skippedTypes.isEmpty)
    }

    /// Access is reported ahead of Sendable — a `private` type is unusable for
    /// the more basic reason, and naming Sendable would send the user to add a
    /// conformance that changes nothing.
    @Test("access outranks Sendable when both apply")
    func accessOutranksSendable() {
        let map = scan("private struct Both: Equatable { let a: Int }")
        #expect(map.skippedTypes.map(\.reason) == [.notNameable(.private)])
    }

    // MARK: - Reporting

    @Test("the generated header states what was skipped and why")
    func headerExplainsTheSkip() {
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: scan("""
        public struct Bare: Equatable { public let a: Int }
        private struct Hidden: Equatable { let a: Int }
        """))
        #expect(output.contains("Detected but skipped"))
        #expect(output.contains("Hidden: declared `private`"))
        #expect(output.contains("Bare: `public` without a `Sendable` conformance"))
        #expect(output.contains("struct HiddenPropertyLawTests") == false)
        #expect(output.contains("struct BarePropertyLawTests") == false)
    }

    @Test("nothing is reported when every type is usable")
    func nothingReportedWhenAllUsable() {
        let map = scan("public struct Foo: Equatable, Sendable { public let a: Int }")
        #expect(map.skippedTypes.isEmpty)
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map)
        #expect(output.contains("Detected but skipped") == false)
    }
}
