import Foundation
@testable import PropertyLawDiscoveryTool
import Testing

/// Collects what `run` writes to each stream.
private final class CapturedOutput {
    var standardOutput = ""
    var standardError = ""

    var output: ToolOutput {
        ToolOutput(
            writeStandardOutput: { self.standardOutput += $0 },
            writeStandardError: { self.standardError += $0 }
        )
    }
}

/// A temporary directory of Swift sources, removed by `remove()`.
private struct Fixture {
    let directory: String
    let sourcePaths: [String]

    init(files: [String: String]) throws {
        directory = NSTemporaryDirectory().appending("PropertyLawRun-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        var paths: [String] = []
        for (name, contents) in files.sorted(by: { $0.key < $1.key }) {
            let path = directory + name
            try contents.write(toFile: path, atomically: true, encoding: .utf8)
            paths.append(path)
        }
        sourcePaths = paths
    }

    func path(_ relative: String) -> String {
        directory + relative
    }

    /// Writes a file into the directory without making it one of the
    /// sources, as a dependency's source passed with `--context-files` is.
    func write(_ name: String, _ contents: String) throws -> String {
        let path = directory + name
        try contents.write(toFile: path, atomically: true, encoding: .utf8)
        return path
    }

    /// The tool's arguments for these sources, with `extra` flags before
    /// `--source-files`.
    func arguments(output: String, _ extra: [String] = []) -> [String] {
        ["--target", "Module", "--output", output] + extra + ["--source-files"] + sourcePaths
    }

    func remove() {
        try? FileManager.default.removeItem(atPath: directory)
    }
}

/// `PropertyLawDiscoveryTool.run(arguments:output:)` is everything `main()`
/// does, so these tests drive the tool the way the plugin does: arguments in,
/// a file on disk and text on the two streams out.
///
/// Before `run` existed no test reached `main()`, and swift-mutation-testing
/// reported its 11 mutants as uncovered: the help dispatch, the `--advisory`
/// branch, and every guard in the summary and the advisory printers.
struct ToolRunTests {

    /// A type the advisory pass flags (an `==` with no `Equatable` declared)
    /// and a curated round-trip pair, so both stderr blocks have something
    /// to say.
    private let advisoryFixture = """
        struct Money {
            let cents: Int
            static func == (lhs: Money, rhs: Money) -> Bool { lhs.cents == rhs.cents }
        }
        enum Codec {
            static func encode(_ value: Money) -> String { String(value.cents) }
            static func decode(_ text: String) -> Money { Money(cents: Int(text) ?? 0) }
        }
        """

    private let derivableFixture = """
        struct Point: Equatable {
            let x: Int
            let y: Int
        }
        """

    // MARK: - Help

    @Test("no arguments, --help and -h print the usage and do nothing else",
          arguments: [[], ["--help"], ["-h"]])
    func helpPrintsUsage(arguments: [String]) throws {
        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(arguments: arguments, output: captured.output)
        #expect(captured.standardOutput == PropertyLawDiscoveryTool.usage + "\n")
        #expect(captured.standardError.isEmpty)
    }

    /// Help is recognised as the first argument only. Anywhere else it is an
    /// unknown flag, as it was before `run` existed.
    @Test func helpAfterAnotherFlagIsAnUnknownArgument() {
        let captured = CapturedOutput()
        #expect(throws: InvocationError.self) {
            try PropertyLawDiscoveryTool.run(
                arguments: ["--target", "Module", "--help"],
                output: captured.output
            )
        }
        #expect(captured.standardOutput.isEmpty)
    }

    @Test func anUnknownFirstArgumentThrowsRatherThanPrintingUsage() {
        let captured = CapturedOutput()
        #expect(throws: InvocationError.self) {
            try PropertyLawDiscoveryTool.run(arguments: ["--bogus"], output: captured.output)
        }
        #expect(captured.standardOutput.isEmpty)
    }

    // MARK: - The generated file and the summary

    @Test func writesTheGeneratedFileAndPrintsTheSummary() throws {
        let fixture = try Fixture(files: ["Point.swift": derivableFixture])
        defer { fixture.remove() }
        // A directory that does not exist yet: the tool creates it.
        let outputPath = fixture.path("Generated/Nested/Out.generated.swift")

        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: outputPath),
            output: captured.output
        )

        let map = ModuleScanner.scan(sourceFiles: fixture.sourcePaths)
        let written = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(written == GeneratedFileEmitter.emit(target: "Module", map: map, suppressions: []))
        #expect(captured.standardOutput == """
            PropertyLawDiscoveryTool: wrote \(outputPath)
              target: Module
              source files scanned: 1
              types detected: 1

            """)
        #expect(captured.standardError.isEmpty)
    }

    @Test func suppressionsInTheExistingFileSurviveAndAreCounted() throws {
        let fixture = try Fixture(files: ["Point.swift": derivableFixture])
        defer { fixture.remove() }
        let outputPath = fixture.path("Out.generated.swift")
        try "    // property-law-suppress: equatable_Point\n"
            .write(toFile: outputPath, atomically: true, encoding: .utf8)

        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: outputPath),
            output: captured.output
        )

        let written = try String(contentsOfFile: outputPath, encoding: .utf8)
        #expect(written.contains("// property-law-suppress: equatable_Point"))
        #expect(captured.standardOutput.contains("\n  suppressions preserved: 1\n"))
    }

    /// `--context-files` and `--extra-import` reach the generated file.
    /// Both of the calls `run` passes them to default the argument to `[]`, so
    /// a `run` that dropped either one would still compile and still write a
    /// file, only without the imports the plugin asked for.
    @Test func contextFilesAndExtraImportsReachTheGeneratedFile() throws {
        let fixture = try Fixture(files: ["Extension.swift": "extension Foreign: Equatable {}"])
        defer { fixture.remove() }
        let contextPath = try fixture.write("Foreign.swift", """
            public struct Foreign: Sendable {
                public let a: Int
            }
            """)
        let plainPath = fixture.path("Plain.generated.swift")
        let withFlagsPath = fixture.path("WithFlags.generated.swift")

        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: plainPath),
            output: CapturedOutput().output
        )
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: withFlagsPath, [
                "--context-files", "OtherModule=\(contextPath)",
                "--extra-import", "PropertyLawSyntax",
            ]),
            output: CapturedOutput().output
        )

        let plain = try String(contentsOfFile: plainPath, encoding: .utf8).split(separator: "\n")
        let withFlags = try String(contentsOfFile: withFlagsPath, encoding: .utf8).split(separator: "\n")
        #expect(!plain.contains("import OtherModule"))
        #expect(!plain.contains("import PropertyLawSyntax"))
        #expect(withFlags.contains("import OtherModule"))
        #expect(withFlags.contains("import PropertyLawSyntax"))
    }

    // MARK: - Scaffolds

    @Test func scaffoldsAreWrittenForAPartiallyDerivableType() throws {
        let fixture = try Fixture(files: [
            "Doc.swift": """
                struct Doc: Equatable {
                    let id: Int
                    let widget: Widget
                }
                """,
        ])
        defer { fixture.remove() }
        let outputPath = fixture.path("Out.generated.swift")
        let scaffoldPath = fixture.path("Scaffolds/Gen.swift")

        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: outputPath, ["--scaffold-out", scaffoldPath]),
            output: captured.output
        )

        let scaffold = try String(contentsOfFile: scaffoldPath, encoding: .utf8)
        #expect(scaffold.contains("extension Doc {"))
        #expect(captured.standardOutput.hasSuffix("\n  scaffolds written: \(scaffoldPath)\n"))
    }

    @Test func noScaffoldFileWhenEveryTypeDerives() throws {
        let fixture = try Fixture(files: ["Point.swift": derivableFixture])
        defer { fixture.remove() }
        let scaffoldPath = fixture.path("Gen.swift")

        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: fixture.path("Out.generated.swift"), ["--scaffold-out", scaffoldPath]),
            output: captured.output
        )

        #expect(!FileManager.default.fileExists(atPath: scaffoldPath))
        #expect(captured.standardOutput.hasSuffix(
            "\n  scaffolds: none (no partially-derivable types)\n"
        ))
    }

    // MARK: - Advisory

    @Test func withoutAdvisoryNothingGoesToStandardError() throws {
        let fixture = try Fixture(files: ["Money.swift": advisoryFixture])
        defer { fixture.remove() }

        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: fixture.path("Out.generated.swift")),
            output: captured.output
        )

        #expect(captured.standardError.isEmpty)
    }

    /// Both detectors report on stderr, and the generated file is
    /// byte-identical to the one written without `--advisory` (PRD §5.4).
    @Test func advisoryWritesBothBlocksToStandardErrorAndLeavesTheFileAlone() throws {
        let fixture = try Fixture(files: ["Money.swift": advisoryFixture])
        defer { fixture.remove() }
        let plainPath = fixture.path("Plain.generated.swift")
        let advisoryPath = fixture.path("Advisory.generated.swift")

        let plain = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: plainPath),
            output: plain.output
        )
        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: advisoryPath, ["--advisory"]),
            output: captured.output
        )

        let map = ModuleScanner.scan(sourceFiles: fixture.sourcePaths)
        let expected = PropertyLawDiscoveryTool.advisoryLines(AdvisorySuggester.suggest(from: map))
            + PropertyLawDiscoveryTool.roundTripLines(RoundTripSuggester.suggest(from: map))
        #expect(captured.standardError.hasPrefix(
            "PropertyLawDiscoveryTool: 1 advisory suggestion(s):\n"
        ))
        #expect(captured.standardError.contains(
            "\nPropertyLawDiscoveryTool: 1 round-trip pair candidate(s):\n"
        ))
        #expect(captured.standardError == expected.joined(separator: "\n") + "\n")
        #expect(
            try String(contentsOfFile: advisoryPath, encoding: .utf8)
                == String(contentsOfFile: plainPath, encoding: .utf8)
        )
    }

    /// With nothing to suggest, `--advisory` prints nothing at all: no header
    /// announcing zero suggestions, and no empty line.
    @Test func advisoryWithNothingToSuggestWritesNothing() throws {
        let fixture = try Fixture(files: ["Point.swift": derivableFixture])
        defer { fixture.remove() }

        let outputPath = fixture.path("Out.generated.swift")

        let captured = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: outputPath, ["--advisory", "--advisory-min", "low"]),
            output: captured.output
        )

        #expect(captured.standardError.isEmpty)
    }

    /// `--advisory-min` reaches the round-trip detector. A pair whose
    /// signatures invert but whose names are not a curated pair is a
    /// medium-confidence candidate, so the default `high` floor hides it.
    ///
    /// The same flag also reaches the missing-conformance detector, but every
    /// suggestion that detector makes is `high`, so no floor changes its
    /// output and no test can show the flag arriving there.
    @Test func advisoryMinLowersTheRoundTripFloor() throws {
        let fixture = try Fixture(files: [
            "Codec.swift": """
                struct Money {
                    let cents: Int
                }
                enum Codec {
                    static func wrap(_ value: Money) -> String { String(value.cents) }
                    static func unwrap(_ text: String) -> Money { Money(cents: Int(text) ?? 0) }
                }
                """,
        ])
        defer { fixture.remove() }
        let outputPath = fixture.path("Out.generated.swift")

        let atDefaultFloor = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: outputPath, ["--advisory"]),
            output: atDefaultFloor.output
        )
        let atMedium = CapturedOutput()
        try PropertyLawDiscoveryTool.run(
            arguments: fixture.arguments(output: outputPath, ["--advisory", "--advisory-min", "medium"]),
            output: atMedium.output
        )

        #expect(atDefaultFloor.standardError.isEmpty)
        #expect(atMedium.standardError.hasPrefix(
            "PropertyLawDiscoveryTool: 1 round-trip pair candidate(s):\n"
        ))
        #expect(atMedium.standardError.contains("Codec.unwrap(_:) and Codec.wrap(_:)"))
        #expect(atMedium.standardError.contains("\n        confidence: medium\n"))
    }
}
