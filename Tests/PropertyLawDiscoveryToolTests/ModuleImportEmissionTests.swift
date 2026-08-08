import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// **The generated file emitted no import of the module under test at all.**
///
/// Every suite named `Foo` with only `Testing` and `PropertyLawKit` in scope,
/// so nothing the plugin produced could compile. Measured across
/// swift-collections, swift-numerics and swift-async-algorithms: 180 detected
/// types, none of them nameable.
///
/// The existing golden tests could not catch it — they assert
/// `output.contains("import PropertyLawKit")`, and a `contains` check on a
/// present line says nothing about an absent one. This file pins the line that
/// was missing, which is the only assertion shape that would have failed.
///
/// `@testable` rather than a plain import is load-bearing: roughly half the
/// types in that corpus are `internal` (20 public / 19 not, on unique names),
/// and a plain import would compile for the public half while dropping the
/// rest. It also matches what `AccessLevel.isCallable(from: .separateFile)`
/// assumes — that `internal` is in reach and `private` is not.
struct ModuleImportEmissionTests {

    private func map(_ entries: [ConformanceMap.Entry]) -> ConformanceMap {
        ConformanceMap(entries: entries, parseFailures: [])
    }

    private func entry(_ name: String) -> ConformanceMap.Entry {
        ConformanceMap.Entry(
            typeName: name,
            conformances: [.equatable],
            provenances: [ConformanceMap.Provenance(
                filePath: "\(name).swift", line: 1, kind: .primary
            )],
            derivationStrategy: .userGen
        )
    }

    @Test("the module under test is imported, testably")
    func emitsTestableImport() {
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map([entry("Foo")]))
        #expect(output.contains("@testable import MyModule"))
    }

    /// A plain `import MyModule` would satisfy a naive `contains` check while
    /// leaving every internal type unreachable.
    @Test("the import is not the plain form")
    func importIsNotPlain() {
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map([entry("Foo")]))
        let plainOnly = output
            .split(separator: "\n")
            .contains { $0 == "import MyModule" }
        #expect(plainOnly == false)
    }

    /// The import belongs with the other imports, ahead of the first suite —
    /// a Swift file cannot import after a declaration.
    @Test("the import precedes every emitted suite")
    func importPrecedesSuites() {
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map([entry("Foo")]))
        let importIndex = output.range(of: "@testable import MyModule")?.lowerBound
        let suiteIndex = output.range(of: "@Suite struct")?.lowerBound
        #expect(importIndex != nil)
        #expect(suiteIndex != nil)
        if let importIndex, let suiteIndex { #expect(importIndex < suiteIndex) }
    }

    /// Emitted even with nothing to test, so an empty target's file still
    /// compiles rather than becoming valid only once a type appears.
    @Test("the import is emitted for an empty target")
    func emitsForEmptyTarget() {
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map([]))
        #expect(output.contains("@testable import MyModule"))
    }

    /// Regeneration-as-diff (PRD §5.3): same input, byte-identical output.
    @Test("adding the import kept emission deterministic")
    func stillDeterministic() {
        let first = GeneratedFileEmitter.emit(target: "MyModule", map: map([entry("Foo")]))
        let second = GeneratedFileEmitter.emit(target: "MyModule", map: map([entry("Foo")]))
        #expect(first == second)
    }
}
