import Foundation
@testable import PropertyLawDiscoveryTool
import Testing

/// PRD §5.5 round-trip discovery (M5) — scanner-side recording. The
/// suggester logic that pairs these up lives in `RoundTripSuggesterTests`;
/// this suite only verifies that `ModuleScanner` populates
/// `memberFunctions` and `topLevelFunctions` correctly.
struct ModuleScannerRoundTripTests {

    @Test func recordsMemberFunctionSignaturesFromPrimaryDeclaration() throws {
        let dir = try makeFixtureDir([
            "Codec.swift": """
                struct Codec {
                    static func encode(_ x: Foo) -> Data { Data() }
                    static func decode(_ d: Data) -> Foo { fatalError() }
                }
                """,
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let functions = try #require(map.memberFunctions["Codec"])
        try #require(functions.count == 2)
        let names = Set(functions.map(\.name))
        #expect(names == ["encode", "decode"])
        for sig in functions {
            #expect(sig.isStatic)
            #expect(sig.parameterTypes.count == 1)
        }
    }

    @Test func aggregatesMemberFunctionsAcrossExtensions() throws {
        // Member functions defined in primary + extensions across files
        // must concatenate into a single per-type list — same aggregation
        // contract as inheritance names and witnesses.
        let dir = try makeFixtureDir([
            "Codec.swift": """
                struct Codec {
                    static func encode(_ x: Foo) -> Data { Data() }
                }
                """,
            "Codec+Decode.swift": """
                extension Codec {
                    static func decode(_ d: Data) -> Foo { fatalError() }
                }
                """,
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let functions = try #require(map.memberFunctions["Codec"])
        let names = Set(functions.map(\.name))
        #expect(names == ["encode", "decode"])
    }

    @Test func recordsTopLevelFreeFunctions() throws {
        // PRD §5.5 module scope: top-level free functions are pairing
        // candidates alongside same-type member functions.
        let dir = try makeFixtureDir([
            "Pair.swift": """
                func serialize(_ x: Foo) -> Data { Data() }
                func deserialize(_ d: Data) -> Foo { fatalError() }
                """,
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let names = Set(map.topLevelFunctions.map(\.name))
        #expect(names == ["serialize", "deserialize"])
        for sig in map.topLevelFunctions {
            #expect(sig.isStatic == false)
            #expect(sig.parameterTypes.count == 1)
        }
    }

    @Test func parsesDiscoverableGroupAttributeOnMemberFunctions() throws {
        // The @Discoverable(group:) attribute is captured syntactically
        // from a string literal; non-literal arguments leave group = nil.
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo {
                    @Discoverable(group: "ser")
                    static func toBytes(_ x: Foo) -> Data { Data() }

                    @Discoverable(group: "ser")
                    static func fromBytes(_ d: Data) -> Foo { fatalError() }

                    static func untagged(_ x: Foo) -> Data { Data() }
                }
                """,
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let functions = try #require(map.memberFunctions["Foo"])
        let byName = Dictionary(uniqueKeysWithValues: functions.map { ($0.name, $0) })
        #expect(byName["toBytes"]?.group == "ser")
        #expect(byName["fromBytes"]?.group == "ser")
        #expect(byName["untagged"]?.group == nil)
    }

    @Test func memberFunctionsAreEmptyForTypeWithoutFuncs() throws {
        // A plain data type with no `func` members shouldn't appear in
        // the memberFunctions map (mirrors the witnesses/empty contract).
        let dir = try makeFixtureDir([
            "Plain.swift": """
                struct Plain {
                    let value: Int
                }
                """,
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        #expect(map.memberFunctions["Plain"] == nil)
    }

    @Test func skipsGenericMemberFunctions() throws {
        // PRD §5.5 stays syntactic — generic functions need type-binding
        // inference, so the finder drops them. They must not surface in
        // the memberFunctions list.
        let dir = try makeFixtureDir([
            "Generic.swift": """
                struct Box {
                    static func wrap<T>(_ x: T) -> Wrapped<T> { fatalError() }
                    static func unwrap<T>(_ w: Wrapped<T>) -> T { fatalError() }
                    static func plain(_ d: Data) -> Foo { fatalError() }
                }
                """,
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let functions = try #require(map.memberFunctions["Box"])
        let names = functions.map(\.name)
        #expect(names == ["plain"])
    }

    // MARK: - Helpers

    private func makeFixtureDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory().appending("PropertyLawScanRT-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        for (name, contents) in files {
            try contents.write(
                toFile: dir + name,
                atomically: true,
                encoding: .utf8
            )
        }
        return dir
    }

    private func filePaths(in dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir).map { dir + $0 }) ?? []
    }
}
