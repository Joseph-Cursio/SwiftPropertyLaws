import Foundation
import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// Three small syntactic signals the scanner reads. A swift-mutation-testing
/// run over `Sources/PropertyLawDiscoveryTool` (2026-10-29) inverted each of
/// them and the whole target still passed.
///
/// - **`static func gen()`** makes a type's generator the user's own, the
///   first tier of PRD §5.7. No test scanned a source that declared one, so a
///   detector that took any static method instead, or only an instance
///   `gen()`, passed.
/// - **`static func ==`** is the Equatable witness. Every fixture with a
///   static method declared `==` or `<`, so a detector that took any static
///   method for `==` passed.
/// - **Provenances** are sorted by file, then line, then kind, and the
///   generated file prints them. The fixtures already listed them in that
///   order, so neither half of the comparison was needed.
struct ScannerSignalTests {

    private func scan(_ files: [String: String]) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawSignal-\(UUID().uuidString)/")
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

    private func strategy(of typeName: String, in map: ConformanceMap) -> DerivationStrategy? {
        map.entries.first { $0.typeName == typeName }?.derivationStrategy
    }

    // MARK: - static func gen()

    /// The scanner reads the method's name and modifiers only, so the return
    /// type here is beside the point.
    @Test(
        "a `static func gen()` makes the generator the user's",
        arguments: [
            ["Foo.swift": """
            public struct Foo: Equatable, Sendable {
                public let a: Int
                public static func gen() -> Int { 0 }
            }
            """],
            [
                "Foo.swift": "public struct Foo: Equatable, Sendable { public let a: Int }",
                "Foo+Gen.swift": "extension Foo { public static func gen() -> Int { 0 } }"
            ]
        ]
    )
    func staticGenIsTheUsersGenerator(files: [String: String]) {
        #expect(strategy(of: "Foo", in: scan(files)) == .userGen)
    }

    @Test(
        "an instance `gen()` or another static method is not the user's generator",
        arguments: [
            "public func gen() -> Int { 0 }",
            "public static func make() -> Int { 0 }"
        ]
    )
    func otherMethodsAreNotTheUsersGenerator(member: String) {
        let map = scan(["Foo.swift": """
        public struct Foo: Equatable, Sendable {
            public let a: Int
            \(member)
        }
        """])
        guard case .memberwiseArbitrary = strategy(of: "Foo", in: map) else {
            Issue.record("expected the memberwise derivation, not \(String(describing: strategy(of: "Foo", in: map)))")
            return
        }
    }

    // MARK: - Operator witnesses

    @Test("a static method other than `==` or `<` is no witness")
    func staticMethodIsNoOperatorWitness() {
        let map = scan(["Plain.swift": """
        struct Plain {
            let value: Int
            static func make() -> Plain { Plain(value: 0) }
        }
        """])
        #expect(map.witnesses["Plain"] == nil)
    }

    // MARK: - Provenance order

    /// `A.swift` sorts first but declares `Foo` on a later line than
    /// `B.swift` extends it, and within `A.swift` the declaration comes
    /// before an extension whose kind sorts first. Sorting by line alone, or
    /// by kind before line, gives a different list.
    @Test("provenances are listed by file, then line, then kind")
    func provenanceOrder() {
        let map = scan([
            "A.swift": """
            // Foo is declared on line 3.

            public struct Foo: Equatable, Sendable { public let a: Int }

            extension Foo: Hashable {}
            """,
            "B.swift": "extension Foo: Comparable { public static func < (lhs: Foo, rhs: Foo) -> Bool { false } }"
        ])
        let provenances = map.entries.first { $0.typeName == "Foo" }?.provenances ?? []
        let listed = provenances.map {
            "\(URL(fileURLWithPath: $0.filePath).lastPathComponent):\($0.line) \($0.kind.rawValue)"
        }
        #expect(listed == ["A.swift:3 primary", "A.swift:5 extension", "B.swift:1 extension"])
    }
}
