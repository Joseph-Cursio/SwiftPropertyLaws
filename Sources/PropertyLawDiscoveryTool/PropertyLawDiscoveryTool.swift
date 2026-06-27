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
struct PropertyLawDiscoveryTool {
    static func main() throws {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        let invocation = try ToolInvocation(arguments: args)
        let map = ModuleScanner.scan(sourceFiles: invocation.sourceFiles)
        let suppressions = SuppressionParser.parse(existingFileAt: invocation.outputPath)
        let output = GeneratedFileEmitter.emit(
            target: invocation.target,
            map: map,
            suppressions: suppressions
        )
        try writeOutput(output, to: invocation.outputPath)
        printSummary(invocation: invocation, map: map, suppressions: suppressions)

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
            printAdvisory(suggestions)

            let roundTripSuggestions = RoundTripSuggester.suggest(
                from: map,
                minConfidence: invocation.advisoryMinConfidence
            )
            printRoundTripSuggestions(roundTripSuggestions)
        }
    }

    static func printUsage() {
        let usage = """
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
                --source-files <paths>... Required. Source paths the plugin discovers.
                --advisory                Optional. Emit missing-conformance suggestions
                                          to stderr (PRD §5.4). Off by default. Output
                                          is informational only and does not change the
                                          generated file.
                --advisory-min <level>    Optional. Minimum confidence floor: low, medium,
                                          or high. Defaults to high. Lowers the bar for
                                          which advisory suggestions are emitted.
            """
        FileHandle.standardOutput.write(Data((usage + "\n").utf8))
    }

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

    private static func printSummary(
        invocation: ToolInvocation,
        map: ConformanceMap,
        suppressions: Set<String>
    ) {
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
            for (category, count) in buckets.sorted(by: { $0.value > $1.value }) {
                lines.append("    [\(count)] \(category)")
            }
            // List names only for small result sets to keep output scannable.
            if todoEntries.count <= 25 {
                for entry in todoEntries {
                    lines.append("      - \(entry.typeName)")
                }
            }
        }
        FileHandle.standardOutput.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// Buckets a `.todo` strategy's reason into a coarse derivation-gap
    /// category for the summary scoreboard.
    private static func todoCategory(for strategy: DerivationStrategy) -> String {
        guard case .todo(let reason) = strategy else { return "n/a" }
        if reason.contains("structs only") { return "non-struct (class/actor/enum-payload)" }
        if reason.contains("no stored properties") { return "no visible stored properties" }
        if reason.contains("user `init") { return "user-defined init" }
        if reason.contains("memberwise derivation supports up to") { return "arity > 10" }
        if reason.contains("stored property") { return "unsupported member type (nested/custom)" }
        if reason.contains("not `CaseIterable`") { return "enum without CaseIterable/raw" }
        return "other"
    }

    /// Render advisory suggestions as Swift-compiler-style `note:` lines
    /// on stderr. One block per suggestion with two indented detail
    /// lines — matches PRD §5.4's "informational, never a test failure"
    /// framing without ever touching the generated file.
    private static func printAdvisory(_ suggestions: [Suggestion]) {
        guard !suggestions.isEmpty else { return }
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
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// Render round-trip suggestions as `note:` blocks on stderr — same
    /// shape as `printAdvisory` so a user reading the advisory output
    /// sees a uniform format. PRD §5.5 framing: informational only.
    private static func printRoundTripSuggestions(_ suggestions: [RoundTripSuggestion]) {
        guard !suggestions.isEmpty else { return }
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
        FileHandle.standardError.write(Data((lines.joined(separator: "\n") + "\n").utf8))
    }
}

/// Argv-parsed invocation. Plugin → tool argv shape:
/// `--target <name> --output <path> [--advisory] [--advisory-min <level>]
///  --source-files <p1> <p2> ...`
struct ToolInvocation: Sendable {
    let target: String
    let outputPath: String
    let sourceFiles: [String]
    let advisory: Bool
    let advisoryMinConfidence: SuggestionConfidence

    init(arguments: [String]) throws {
        var builder = Builder()
        var index = 0
        while index < arguments.count {
            index = try Self.advance(arguments: arguments, from: index, into: &builder)
        }
        try self.init(builder: builder)
    }

    private init(builder: Builder) throws {
        guard let target = builder.target else {
            throw InvocationError.missingValue("--target")
        }
        guard let outputPath = builder.outputPath else {
            throw InvocationError.missingValue("--output")
        }
        self.target = target
        self.outputPath = outputPath
        self.sourceFiles = builder.sourceFiles
        self.advisory = builder.advisory
        self.advisoryMinConfidence = builder.advisoryMin
    }

    /// Mutable accumulator for the argv loop — keeps `init(arguments:)`
    /// under the cyclomatic-complexity / function-length lints.
    private struct Builder {
        var target: String?
        var outputPath: String?
        var sourceFiles: [String] = []
        var advisory = false
        var advisoryMin: SuggestionConfidence = .high
    }

    /// Consumes one flag (and its value, if any) from `arguments` and
    /// returns the next index. The dispatch lives here so the init
    /// itself stays a tight while loop.
    private static func advance(
        arguments: [String],
        from index: Int,
        into builder: inout Builder
    ) throws -> Int {
        let arg = arguments[index]
        switch arg {
        case "--target":
            builder.target = try requireValue(after: arg, arguments: arguments, at: index)
            return index + 2
        case "--output":
            builder.outputPath = try requireValue(after: arg, arguments: arguments, at: index)
            return index + 2
        case "--advisory":
            builder.advisory = true
            return index + 1
        case "--advisory-min":
            let raw = try requireValue(after: arg, arguments: arguments, at: index)
            guard let level = SuggestionConfidence(rawValue: raw) else {
                throw InvocationError.invalidValue(
                    flag: arg, value: raw, allowed: "low | medium | high"
                )
            }
            builder.advisoryMin = level
            return index + 2
        case "--source-files":
            return consumeSourceFiles(arguments: arguments, from: index + 1, into: &builder)
        default:
            throw InvocationError.unknownArgument(arg)
        }
    }

    private static func requireValue(
        after flag: String,
        arguments: [String],
        at index: Int
    ) throws -> String {
        let next = index + 1
        guard next < arguments.count else {
            throw InvocationError.missingValue(flag)
        }
        return arguments[next]
    }

    /// `--source-files` greedily consumes positional arguments until the
    /// next `--`-prefixed flag (or end of input).
    private static func consumeSourceFiles(
        arguments: [String],
        from start: Int,
        into builder: inout Builder
    ) -> Int {
        var index = start
        while index < arguments.count, !arguments[index].hasPrefix("--") {
            builder.sourceFiles.append(arguments[index])
            index += 1
        }
        return index
    }
}

enum InvocationError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)
    case invalidValue(flag: String, value: String, allowed: String)

    var description: String {
        switch self {
        case .missingValue(let flag): return "missing value for \(flag)"
        case .unknownArgument(let arg): return "unknown argument: \(arg)"
        case .invalidValue(let flag, let value, let allowed):
            return "invalid value '\(value)' for \(flag); allowed: \(allowed)"
        }
    }
}
