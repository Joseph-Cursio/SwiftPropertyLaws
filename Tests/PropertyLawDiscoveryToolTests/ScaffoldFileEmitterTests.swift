import Foundation
import Testing
@testable import PropertyLawDiscoveryTool
@testable import PropertyLawCore

/// The scaffold file collects `gen()` stubs only for partially-derivable
/// `.todo` types — fully-derivable types (auto-test file) and non-scaffoldable
/// ones (classes / external) are excluded.
struct ScaffoldFileEmitterTests {

    @Test func emitsStubsOnlyForPartiallyDerivableTypes() throws {
        let dir = try makeFixtureDir([
            "Models.swift": """
                struct Doc: Equatable {        // partial: url has no generator
                    let id: Int
                    let url: URL
                }
                struct Point: Equatable {       // fully derivable → no scaffold
                    let x: Int
                    let y: Int
                }
                final class Box: Equatable {    // class → not scaffoldable
                    let value: Int
                    init(value: Int) { self.value = value }
                    static func == (l: Box, r: Box) -> Bool { l.value == r.value }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let scaffold = try #require(ScaffoldFileEmitter.emit(map: map))

        #expect(scaffold.contains("extension Doc {"))
        #expect(scaffold.contains("<#Generator<URL>#>"))
        #expect(scaffold.contains("Doc(id: $0.0, url: $0.1)"))
        #expect(scaffold.contains("import PropertyLawKit"))
        // Fully-derivable and class types are not scaffolded.
        #expect(scaffold.contains("extension Point") == false)
        #expect(scaffold.contains("extension Box") == false)
        #expect(scaffold.contains("1 type(s) partially derived"))
    }

    @Test func returnsNilWhenNothingScaffoldable() throws {
        let dir = try makeFixtureDir([
            "Plain.swift": """
                struct Point: Equatable { let x: Int; let y: Int }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        #expect(ScaffoldFileEmitter.emit(map: map) == nil)
    }

    private func makeFixtureDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory().appending("PropertyLawScaffold-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for (name, contents) in files {
            try contents.write(toFile: dir + name, atomically: true, encoding: .utf8)
        }
        return dir
    }

    private func filePaths(in dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir).map { dir + $0 }) ?? []
    }
}
