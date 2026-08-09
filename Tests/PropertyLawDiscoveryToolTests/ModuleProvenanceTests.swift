import Foundation
import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// `--context-files` told the scanner which types *exist*; it did not say which
/// module to `import` for them. So a suite for a type this target merely
/// extends still could not name it — the same defect the `@testable import
/// <Target>` line was added to fix, one module over.
///
/// Attributing context entries as `Module=path` closes it, and forces a second
/// rule: a foreign type is reachable only through a **plain** `import`, because
/// `@testable` is emitted for the scanned target alone and across a package
/// boundary needs the dependency built with testability. So a foreign
/// `internal` type is out of reach however the imports are written, and is
/// skipped rather than emitted.
struct ModuleProvenanceTests {

    /// A context file plus the module the caller attributes it to.
    private struct ContextFile {
        let module: String?
        let name: String
        let source: String
    }

    private func scan(
        target: [String: String],
        context: [ContextFile] = []
    ) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawProv-\(UUID().uuidString)/")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        var targetPaths: [String] = []
        for (name, contents) in target {
            let path = dir + "t_" + name
            try? contents.write(toFile: path, atomically: true, encoding: .utf8)
            targetPaths.append(path)
        }
        var contextEntries: [String] = []
        for entry in context {
            let path = dir + "c_" + entry.name
            try? entry.source.write(toFile: path, atomically: true, encoding: .utf8)
            contextEntries.append(entry.module.map { "\($0)=\(path)" } ?? path)
        }
        return ModuleScanner.scan(sourceFiles: targetPaths, contextFiles: contextEntries)
    }

    private let foreignPublic = """
    public struct Foreign: Sendable {
        public let a: Int
    }
    """

    // MARK: - Attribution parsing

    @Test("a Module=path entry splits into both")
    func attributionSplits() {
        let parsed = ModuleScanner.attributed("SwiftSyntax=/tmp/A.swift")
        #expect(parsed.module == "SwiftSyntax")
        #expect(parsed.path == "/tmp/A.swift")
    }

    /// A caller that does not know or care which module a file belongs to keeps
    /// working — attribution is additive.
    @Test("a bare path stays unattributed")
    func barePathUnattributed() {
        let parsed = ModuleScanner.attributed("/tmp/A.swift")
        #expect(parsed.module == nil)
        #expect(parsed.path == "/tmp/A.swift")
    }

    /// A path may legitimately contain `=`, and misreading one as a module
    /// would emit an import for a directory fragment.
    @Test("a path containing = is not mistaken for attribution")
    func pathWithEqualsIsNotAttribution() {
        let parsed = ModuleScanner.attributed("/tmp/a=b/File.swift")
        #expect(parsed.module == nil)
        #expect(parsed.path == "/tmp/a=b/File.swift")
    }

    // MARK: - The emitted imports

    @Test("a foreign type's module is imported, plainly")
    func foreignModuleImported() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: [ContextFile(module: "OtherModule", name: "F.swift", source: foreignPublic)]
        )
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.contains("import OtherModule"))
        // Plain, not `@testable`: we can only reach its public API anyway.
        #expect(output.contains("@testable import OtherModule") == false)
        // The target keeps `@testable`, which is what reaches its own internals.
        #expect(output.contains("@testable import MyTarget"))
    }

    @Test("an unattributed context type emits no import")
    func unattributedEmitsNoImport() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: [ContextFile(module: nil, name: "F.swift", source: foreignPublic)]
        )
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.contains("import OtherModule") == false)
    }

    /// **A name declared on both sides belongs to the target**, so no foreign
    /// import is emitted for it. A mutant that let the context attribution
    /// stick survived until this asserted a *different* module name — with
    /// `MyTarget` on both sides the emitter's self-import guard hid the bug.
    @Test("a name declared in both target and context is the target's")
    func targetDeclarationClearsForeignModule() {
        let map = scan(
            target: ["T.swift": "public struct Foreign: Equatable, Sendable { public let a: Int }"],
            context: [ContextFile(module: "OtherModule", name: "F.swift", source: foreignPublic)]
        )
        #expect(map.entries.first(where: { $0.typeName == "Foreign" })?.declaringModule == nil)
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.contains("import OtherModule") == false)
    }

    /// The target's own module must never be imported, from any source — a
    /// caller passing it via `--extra-import` would otherwise emit a file that
    /// imports itself.
    @Test("the target is never imported, even if asked for")
    func targetNeverImportsItself() {
        let map = scan(
            target: ["T.swift": "public struct Mine: Equatable, Sendable { public let a: Int }"]
        )
        let output = GeneratedFileEmitter.emit(
            target: "MyTarget", map: map, extraImports: ["MyTarget"]
        )
        let plainSelfImport = output.split(separator: "\n").contains { $0 == "import MyTarget" }
        #expect(plainSelfImport == false)
        #expect(output.contains("@testable import MyTarget"))
    }

    @Test("extraImports are emitted and deduplicated with inferred ones")
    func extraImportsEmitted() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: [ContextFile(module: "OtherModule", name: "F.swift", source: foreignPublic)]
        )
        let output = GeneratedFileEmitter.emit(
            target: "MyTarget", map: map, extraImports: ["PropertyLawSyntax", "OtherModule"]
        )
        #expect(output.contains("import PropertyLawSyntax"))
        let occurrences = output.split(separator: "\n").filter { $0 == "import OtherModule" }
        #expect(occurrences.count == 1, "OtherModule imported \(occurrences.count) times")
    }

    /// PRD §5.3 regeneration-as-diff: the import block has to be ordered, not
    /// set-ordered.
    @Test("imports are deterministic")
    func importsAreDeterministic() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: [ContextFile(module: "OtherModule", name: "F.swift", source: foreignPublic)]
        )
        let first = GeneratedFileEmitter.emit(
            target: "MyTarget", map: map, extraImports: ["Zed", "Alpha"]
        )
        let second = GeneratedFileEmitter.emit(
            target: "MyTarget", map: map, extraImports: ["Alpha", "Zed"]
        )
        #expect(first == second)
    }

    // MARK: - The foreign-access rule

    /// The rule this work forced. Without it, module provenance would trade one
    /// uncompilable emission for another: a plain `import` cannot reach an
    /// `internal` type in someone else's module.
    @Test("a foreign internal type is skipped, not emitted")
    func foreignInternalSkipped() {
        let map = scan(
            target: ["E.swift": "extension Hidden: Equatable {}"],
            context: [ContextFile(module: "OtherModule", name: "F.swift", source: """
            struct Hidden: Sendable {
                let a: Int
            }
            """)]
        )
        #expect(map.entries.isEmpty)
        #expect(map.skippedTypes.map(\.reason) == [.foreignNonPublic("OtherModule")])
    }

    @Test("the skip explanation names the module")
    func foreignSkipNamesTheModule() {
        let map = scan(
            target: ["E.swift": "extension Hidden: Equatable {}"],
            context: [ContextFile(
                module: "OtherModule", name: "F.swift",
                source: "struct Hidden: Sendable { let a: Int }"
            )]
        )
        #expect(map.skippedTypes.first?.explanation.contains("`OtherModule`") == true)
        #expect(map.skippedTypes.first?.explanation.contains("only reachable through a plain import") == true)
    }

    /// A foreign *public* type is fine — that is the whole point of importing
    /// its module.
    @Test("a foreign public type is kept")
    func foreignPublicKept() {
        let map = scan(
            target: ["E.swift": "extension Foreign: Equatable {}"],
            context: [ContextFile(module: "OtherModule", name: "F.swift", source: foreignPublic)]
        )
        #expect(map.entries.map(\.typeName) == ["Foreign"])
        #expect(map.skippedTypes.isEmpty)
    }

    /// An `internal` type the *target* declares stays reachable — `@testable`
    /// promotes it. The rule must key on foreignness, not on access alone.
    @Test("the target's own internal types are unaffected")
    func targetInternalUnaffected() {
        let map = scan(target: ["T.swift": "struct Mine: Equatable { let a: Int }"])
        #expect(map.entries.map(\.typeName) == ["Mine"])
        #expect(map.skippedTypes.isEmpty)
    }
}
