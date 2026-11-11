import Foundation
import PropertyLawCore
@testable import PropertyLawDiscoveryTool
import SwiftParser
import SwiftSyntax
import Testing

/// The `.todo` arm now ends in a trailing `//` comment, which is safe **only**
/// because that expression always lands last on its line. That is a property of
/// the callers, not of the emitter, and callers change — `GeneratorResolver` and
/// `ScaffoldEmitter` both splice expressions *into* larger ones and are safe
/// today only because they `return nil` on `.todo` first.
///
/// So rather than assert the invariant in a comment, parse whole emitted files
/// and require them to be syntactically valid. A marker that ever swallowed the
/// rest of a line would show up here as a parse error, whatever caller
/// introduced it.
struct EmittedFileParsesTests {

    private func scan(_ source: String) -> ConformanceMap {
        let dir = NSTemporaryDirectory().appending("PropertyLawParse-\(UUID().uuidString)/")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let path = dir + "Sample.swift"
        try? source.write(toFile: path, atomically: true, encoding: .utf8)
        return ModuleScanner.scan(sourceFiles: [path])
    }

    /// Collects the parser's own diagnostics — `Parser.parse` always returns a
    /// tree, inserting missing tokens, so "did it parse" has to be asked of the
    /// diagnostics rather than of the result being non-nil.
    private func syntaxErrors(in source: String) -> [String] {
        let tree = Parser.parse(source: source)
        var errors: [String] = []
        // A token the parser had to invent to keep going is exactly what a
        // swallowed line looks like.
        for token in tree.tokens(viewMode: .all) where token.presence == .missing {
            errors.append("missing token near `\(token.text)`")
        }
        if tree.hasError { errors.append("tree.hasError") }
        return errors
    }

    /// A file containing a `.todo` — the case the marker is on.
    @Test("an emitted file with a todo generator parses")
    func todoFileParses() {
        let map = scan("""
        public struct Opaque: Equatable, Sendable {
            public let thing: SomeUnresolvableType
        }
        """)
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.contains(GeneratorExpressionEmitter.todoMarker))
        #expect(syntaxErrors(in: output).isEmpty, "\(syntaxErrors(in: output))")
    }

    /// A mixed file — a derived suite next to a todo one — because the hazard is
    /// a comment running into whatever the emitter writes next.
    @Test("an emitted file mixing derived and todo generators parses")
    func mixedFileParses() {
        let map = scan("""
        public struct Fine: Equatable, Sendable {
            public let a: Int
            public let b: String
        }

        public struct Opaque: Equatable, Sendable {
            public let thing: SomeUnresolvableType
        }

        public enum Colour: String, Equatable, Sendable {
            case red, green
        }
        """)
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.contains(GeneratorExpressionEmitter.todoMarker))
        #expect(output.contains("zip("))
        #expect(syntaxErrors(in: output).isEmpty, "\(syntaxErrors(in: output))")
    }

    /// The nested shapes `ExpressionLayout` places: a memberwise generator
    /// with a multi-line `oneOf` member, a payload case inside a `oneOf`, and
    /// a `oneOf` nested in a `oneOf`. Each puts a continuation line inside
    /// parentheses, so a layout that broke the syntax would show up here. The
    /// test also checks where the lines land. `Code` has raw values, but its
    /// cases are visible to the scanner, so it derives through case
    /// enumeration; the raw-value shape is the next test.
    @Test("an emitted file with nested multi-line generators parses")
    func nestedGeneratorsParse() {
        let map = scan("""
        enum Mode: Equatable, Sendable {
            case on, off
        }

        enum Code: Int, Equatable, Sendable {
            case a = 1, b = 2
        }

        enum Signal: Equatable, Sendable {
            case off
            case dimmed(level: Int, warm: Bool)
            case moded(Mode)
        }

        struct Panel: Equatable, Sendable {
            let level: Int
            let mode: Mode
            let code: Code
            let signal: Signal
        }
        """)
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(syntaxErrors(in: output).isEmpty, "\(syntaxErrors(in: output))")
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Panel's outer `.map` lines up under `using:`, at column 12.
        #expect(lines.contains { $0.hasPrefix("            .map { Panel(level: ") })
        // Signal's payload case keeps its `.map` under its `zip(`, at 16.
        #expect(lines.contains { $0.hasPrefix("                .map { Signal.dimmed(level: ") })
        // Nothing lands at the method's left margin.
        #expect(!lines.contains { $0.hasPrefix("Gen.") || $0.hasPrefix(")") || $0.hasPrefix(".") })
    }

    /// A raw-value member: `Gen<Int>.int()` with its `.compactMap` on the next
    /// line, at column 0, inside the `zip(` and before a comma. A scanned
    /// raw-value enum with visible cases derives through case enumeration, so
    /// the entry is built directly from the strategy the strategist falls back
    /// to when the cases are not visible.
    @Test("an emitted file with a raw-value member inside a zip parses")
    func rawValueMemberInsideAZipParses() {
        let code = GeneratorExpressionEmitter.expression(typeName: "Code", strategy: .rawRepresentable(.int))
        let map = ConformanceMap(
            entries: [
                ConformanceMap.Entry(
                    typeName: "Holder",
                    conformances: [.equatable],
                    provenances: [],
                    derivationStrategy: .memberwiseArbitrary(members: [
                        MemberSpec(name: "code", generatorExpression: code),
                        MemberSpec(name: "count", rawType: .int),
                    ])
                ),
            ],
            parseFailures: []
        )
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(syntaxErrors(in: output).isEmpty, "\(syntaxErrors(in: output))")
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        #expect(lines.contains("            using: zip(Gen<Int>.int()"))
        #expect(lines.contains("            .compactMap { Code(rawValue: $0) }, Gen<Int>.int())"))
        #expect(lines.contains { $0.hasPrefix("            .map { Holder(code: $0.0, count: $0.1) }") })
    }

    /// Multiple todos in one suite: several `@Test` methods, each ending in the
    /// marker, with the next method's lines following.
    @Test("a suite with several todo tests parses")
    func multipleTodoTestsParse() {
        let map = scan("""
        public struct Opaque: Equatable, Hashable, Comparable, Sendable {
            public let thing: SomeUnresolvableType
        }
        """)
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.components(separatedBy: GeneratorExpressionEmitter.todoMarker).count > 2)
        #expect(syntaxErrors(in: output).isEmpty, "\(syntaxErrors(in: output))")
    }

    /// The marker must not appear where it would be wrong — a fully derived file
    /// carries no compile-error warning.
    @Test("a fully derived file carries no marker")
    func derivedFileHasNoMarker() {
        let map = scan("public struct Fine: Equatable, Sendable { public let a: Int }")
        let output = GeneratedFileEmitter.emit(target: "MyTarget", map: map)
        #expect(output.contains(GeneratorExpressionEmitter.todoMarker) == false)
        #expect(syntaxErrors(in: output).isEmpty)
    }

    /// A suppressed todo still parses — the suppression path replaces the test
    /// body, and the marker must not leak into the comment stub.
    @Test("a suppressed todo parses")
    func suppressedTodoParses() {
        let map = scan("""
        public struct Opaque: Equatable, Sendable {
            public let thing: SomeUnresolvableType
        }
        """)
        let output = GeneratedFileEmitter.emit(
            target: "MyTarget", map: map, suppressions: ["equatable_Opaque"]
        )
        #expect(syntaxErrors(in: output).isEmpty, "\(syntaxErrors(in: output))")
    }
}
