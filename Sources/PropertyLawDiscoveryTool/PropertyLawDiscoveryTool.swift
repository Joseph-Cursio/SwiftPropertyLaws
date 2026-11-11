import Foundation
import PropertyLawCore

/// Whole-module conformance-discovery tool (PRD §5.3 Discovery Mode).
///
/// Invoked by `PropertyLawDiscoveryPlugin` via `swift package propertylawcheck
/// discover --target <name>`. The plugin gathers source-file paths from
/// the PluginContext and forwards them as positional arguments after the
/// `--source-files` separator. This tool walks them, builds a
/// `ConformanceMap`, applies any suppression markers found in an existing
/// output file, and writes the rendered output.
@main
enum PropertyLawDiscoveryTool {
    // swiftlint:disable:next unused_declaration - the @main entry point
    static func main() throws {
        try run(arguments: Array(CommandLine.arguments.dropFirst()), output: .standard)
    }

    /// Everything `main()` does, with the arguments and the output streams
    /// passed in rather than read from the process, so a test can call it.
    ///
    /// - Parameters:
    ///   - arguments: the command line without the program name.
    ///   - output: where the usage text, the summary and the advisory notes go.
    static func run(arguments: [String], output: ToolOutput) throws {
        if arguments.isEmpty || arguments.first == "--help" || arguments.first == "-h" {
            output.writeStandardOutput(usage + "\n")
            return
        }

        let invocation = try ToolInvocation(arguments: arguments)
        let map = ModuleScanner.scan(
            sourceFiles: invocation.sourceFiles,
            contextFiles: invocation.contextFiles
        )
        let suppressions = SuppressionParser.parse(existingFileAt: invocation.outputPath)
        let generated = GeneratedFileEmitter.emit(
            target: invocation.target,
            map: map,
            suppressions: suppressions,
            extraImports: invocation.extraImports
        )
        try writeOutput(generated, to: invocation.outputPath)
        output.printLines(summaryLines(invocation: invocation, map: map, suppressions: suppressions))

        // Opt-in scaffold pass — best-effort `gen()` stubs for partially
        // derivable `.todo` types, written to a separate file (placeholders
        // don't compile, so they can't live in the generated test file).
        if let scaffoldPath = invocation.scaffoldOutputPath {
            if let scaffolds = ScaffoldFileEmitter.emit(map: map) {
                try writeOutput(scaffolds, to: scaffoldPath)
                output.printLines(["  scaffolds written: \(scaffoldPath)"])
            } else {
                output.printLines(["  scaffolds: none (no partially-derivable types)"])
            }
        }

        // PRD §5.4 + §5.5 advisory pass — opt-in, writes to stderr only
        // so the generated file stays byte-identical regardless of
        // `--advisory`. Both detectors share the flag and the confidence
        // floor; the user gets one stderr block per detector with a
        // header line so output stays scannable.
        if invocation.advisory {
            let suggestions = AdvisorySuggester.suggest(
                from: map,
                minConfidence: invocation.advisoryMinConfidence
            )
            output.printErrorLines(advisoryLines(suggestions))

            let roundTripSuggestions = RoundTripSuggester.suggest(
                from: map,
                minConfidence: invocation.advisoryMinConfidence
            )
            output.printErrorLines(roundTripLines(roundTripSuggestions))
        }
    }

    /// The text `--help`, `-h` or no arguments at all print.
    static let usage = """
        PropertyLawDiscoveryTool — walks a target's source files and emits
        PropertyLawKit test calls for each detected conformance.

        Usage (typical, via plugin):
            swift package propertylawcheck discover --target <Target>

        Direct invocation:
            PropertyLawDiscoveryTool \\
                --target <Target> \\
                --output <path/to/PropertyLawTests.generated.swift> \\
                --source-files <file1.swift> <file2.swift> ...

        Options:
            --target <name>           Required. The target whose conformances to scan.
            --output <path>           Required. Path to the generated file.
            --scaffold-out <path>     Optional. Write best-effort gen() stubs for
                                      partially-derivable types (with <#...#>
                                      placeholders) to a separate file for review.
            --source-files <paths>... Required. Source paths the plugin discovers.
            --extra-import <Module>   Optional, repeatable. Add an `import <Module>` to
                                      the generated file. Use for a package that supplies
                                      generators the emitted code calls — e.g.
                                      `--extra-import PropertyLawSyntax` so an emitted
                                      `Syntax.gen()` resolves. Never inferred.
            --context-files <paths>...
                                      Optional. Sources of the target's dependencies,
                                      read for declarations only. Types found here get
                                      no suite of their own; they let the scan resolve
                                      members and report accurate diagnostics for types
                                      this target merely extends. Each path may be
                                      prefixed `Module=` so the emitter knows which
                                      module to import for a foreign type.
            --advisory                Optional. Emit missing-conformance suggestions
                                      to stderr (PRD §5.4). Off by default. Output
                                      is informational only and does not change the
                                      generated file.
            --advisory-min <level>    Optional. Minimum confidence floor: low, medium,
                                      or high. Defaults to high. Lowers the bar for
                                      which advisory suggestions are emitted.
        """

    /// Writes `contents` to `path`, creating parent directories as needed.
    private static func writeOutput(_ contents: String, to path: String) throws {
        let url = URL(fileURLWithPath: path)
        let parent = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The summary printed after the generated file is written: what was
    /// scanned, what was skipped and why, and which types still need a
    /// hand-written `gen()`.
    static func summaryLines(
        invocation: ToolInvocation,
        map: ConformanceMap,
        suppressions: Set<String>
    ) -> [String] {
        var lines: [String] = []
        lines.append("PropertyLawDiscoveryTool: wrote \(invocation.outputPath)")
        lines.append("  target: \(invocation.target)")
        lines.append("  source files scanned: \(invocation.sourceFiles.count)")
        lines.append("  types detected: \(map.entries.count)")
        if !map.parseFailures.isEmpty {
            lines.append("  parse failures: \(map.parseFailures.count)")
        }
        if !suppressions.isEmpty {
            lines.append("  suppressions preserved: \(suppressions.count)")
        }
        if !map.skippedTypes.isEmpty {
            lines.append("  detected but skipped, no suite emitted "
                + "(\(map.skippedTypes.count)):")
            for type in map.skippedTypes {
                lines.append("    - \(type.typeName): \(type.explanation)")
            }
        }
        // PRD §5.7 weak-generator telemetry — list types that need a
        // user-supplied gen() because no derivation strategy applied.
        let todoEntries = map.entries.filter { entry in
            if case .todo = entry.derivationStrategy { return true }
            return false
        }
        if !todoEntries.isEmpty {
            lines.append("  types needing manual gen() (\(todoEntries.count)):")
            // Bucket by reason so the dominant derivation gap is visible at a
            // glance — this is the scoreboard for prioritizing which
            // derivation tier to build next.
            var buckets: [String: Int] = [:]
            for entry in todoEntries {
                buckets[Self.todoCategory(for: entry.derivationStrategy), default: 0] += 1
            }
            lines.append(contentsOf: Self.bucketLines(buckets))
            // List names only for small result sets to keep output scannable.
            if todoEntries.count <= 25 {
                for entry in todoEntries {
                    lines.append("      - \(entry.typeName)")
                }
            }
        }
        return lines
    }

    /// Buckets a `.todo` strategy's reason into a coarse derivation-gap
    /// category for the summary scoreboard.
    ///
    /// Matching is on substrings of `TodoReason`'s prose, so the two files are
    /// coupled: a reworded reason silently falls through to `"other"`, and a new
    /// reason that happens to contain an earlier arm's substring is swallowed by
    /// it. `TodoCategoryTests` pins every arm against the strings the strategist
    /// actually produces. Internal rather than private for that reason.
    /// The summary's gap buckets, largest first and ties by name.
    ///
    /// Sorting by count alone left ties in `Dictionary` order, which Swift
    /// randomizes per process, so two runs over the same sources could write
    /// different summaries. Rerunning PRD §8 Pass 1 showed it: the committed
    /// `.summary.txt` files changed between runs with nothing scanned changing.
    static func bucketLines(_ buckets: [String: Int]) -> [String] {
        buckets
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { "    [\($0.value)] \($0.key)" }
    }

    static func todoCategory(for strategy: DerivationStrategy) -> String {
        guard case .todo(let reason) = strategy else { return "n/a" }
        for (needle, category) in categoryTable where reason.contains(needle) {
            return category
        }
        return "other"
    }

    /// Substring → bucket, **in match order**, which is load-bearing in two
    /// places and inert in a third:
    ///
    /// - `"memberwise initializer"` must precede `"stored property"`: the
    ///   access reason says both, and reporting a `private let x: Int` as an
    ///   unsupported member *type* sends the user to fix the one thing that
    ///   isn't wrong.
    /// - the enum arms must precede nothing in particular, but they replaced a
    ///   single `"enum without CaseIterable/raw"` bucket that conflated four
    ///   causes and named the one remedy impossible for the commonest of them
    ///   (an enum with associated values cannot conform to `CaseIterable`).
    /// - `"every initializer the type declares is"` before `"user `init"` is
    ///   *not* load-bearing — the latter matches a phrase the former never
    ///   contains. A mutant swapping them leaves every test green, which is how
    ///   an earlier comment claiming a hazard there was caught.
    ///
    /// A table rather than an `if` ladder because the ladder tripped the
    /// cyclomatic-complexity lint at twelve arms, and the ordering is easier to
    /// read as data.
    private static let categoryTable: [(needle: String, category: String)] = [
        ("only extends the type", "declaration not in this target"),
        ("structs only", "non-struct (class/actor/enum-payload)"),
        ("the class is not `Sendable`", "class not Sendable (a check's inputs must be)"),
        ("no synthesized memberwise initializer", "class with no callable initializer"),
        ("no stored properties", "no stored properties, no callable init()"),
        ("every initializer the type declares is",
         "access-restricted initializer (private/fileprivate)"),
        ("user `init", "user-defined init"),
        ("memberwise derivation supports up to", "arity > 10"),
        ("memberwise initializer", "access-restricted member (private/fileprivate)"),
        ("stored property", "unsupported member type (nested/custom)"),
        ("declares no cases", "caseless enum (uninhabited)"),
        ("associated values; case enumeration", "enum case over the arity limit"),
        ("associated value of type", "enum payload type unresolved"),
        ("neither `CaseIterable` nor", "enum cases not captured"),
    ]

    /// Advisory suggestions as Swift-compiler-style `note:` lines, for
    /// stderr. One block per suggestion with two indented detail lines —
    /// matches PRD §5.4's "informational, never a test failure" framing
    /// without ever touching the generated file. No suggestions, no lines:
    /// not even the header.
    static func advisoryLines(_ suggestions: [Suggestion]) -> [String] {
        guard !suggestions.isEmpty else { return [] }
        var lines: [String] = []
        lines.append("PropertyLawDiscoveryTool: \(suggestions.count) advisory suggestion(s):")
        for suggestion in suggestions {
            let proto = suggestion.suggestedProtocol
            lines.append(
                "  note: \(suggestion.typeName) \(suggestion.evidence) "
                + "but does not declare \(proto.declarationName)."
            )
            lines.append(
                "        Consider conforming and running \(proto.checkFunctionName) "
                + "to verify the laws hold."
            )
            lines.append(
                "        confidence: \(suggestion.confidence.rawValue)"
            )
        }
        return lines
    }

    /// Round-trip suggestions as `note:` blocks, for stderr — same shape
    /// as `advisoryLines` so a user reading the advisory output sees a
    /// uniform format. PRD §5.5 framing: informational only. No
    /// suggestions, no lines.
    static func roundTripLines(_ suggestions: [RoundTripSuggestion]) -> [String] {
        guard !suggestions.isEmpty else { return [] }
        var lines: [String] = []
        lines.append(
            "PropertyLawDiscoveryTool: \(suggestions.count) round-trip pair candidate(s):"
        )
        for suggestion in suggestions {
            let scopeLabel: String
            switch suggestion.scope {
            case .type(let name): scopeLabel = name
            case .module:         scopeLabel = "<module>"
            }
            lines.append(
                "  note: \(scopeLabel).\(suggestion.forward.name)(_:) and "
                + "\(scopeLabel).\(suggestion.backward.name)(_:) form a "
                + "round-trip pair candidate."
            )
            lines.append(
                "        Consider writing a property that asserts "
                + "\(suggestion.backward.name)(\(suggestion.forward.name)(x)) == x "
                + "for all x."
            )
            lines.append(
                "        confidence: \(suggestion.confidence.rawValue)"
            )
            lines.append(
                "        evidence: \(suggestion.evidence)"
            )
        }
        return lines
    }
}
