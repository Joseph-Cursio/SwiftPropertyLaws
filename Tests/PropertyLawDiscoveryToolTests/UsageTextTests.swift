@testable import PropertyLawDiscoveryTool
import Testing

/// The `--help` text is the third copy of the tool's flag list, after
/// `ToolFlag` and the plugin's parser, and the only one a user reads. Nothing
/// compiles it, so these tests are what keep it in step with `ToolFlag` (#89).
struct UsageTextTests {

    /// Each flag must have its own line under `Options:`. A search of the
    /// whole text would not do: `--advisory` is a prefix of `--advisory-min`,
    /// and every required flag also appears in the "Direct invocation" example.
    @Test(arguments: ToolFlag.allCases)
    func everyFlagIsDocumented(flag: ToolFlag) throws {
        let documented = try Self.documentedOptions(in: PropertyLawDiscoveryTool.usage)
        #expect(documented.contains(flag.rawValue))
    }

    /// The other direction: an option line for a flag the tool no longer
    /// takes, or one listed twice, also fails.
    @Test func theOptionsListIsExactlyTheFlags() throws {
        let documented = try Self.documentedOptions(in: PropertyLawDiscoveryTool.usage)
        #expect(documented.sorted() == ToolFlag.allCases.map(\.rawValue).sorted())
    }

    /// Checks the reader below on a text that names `--advisory-min` but not
    /// `--advisory`, and repeats a flag in its example, the two cases where a
    /// plain `contains` would give the wrong answer.
    @Test func optionsAreReadAsWholeWordsFromTheOptionsSection() throws {
        let usage = """
            Example:
                Tool --target <name> \\
                    --output <path>

            Options:
                --target <name>           Required.
                --advisory-min <level>    Optional. Unlike --advisory, takes a value.
                                          --output is mentioned here, not listed.
            """
        #expect(try Self.documentedOptions(in: usage) == ["--target", "--advisory-min"])
    }

    /// The first word of every line under `Options:` that starts with `--` at
    /// the options' own indentation, which the first such line sets. A wrapped
    /// description line is indented further, so one that happens to begin with
    /// a flag is not read as listing it.
    static func documentedOptions(in usage: String) throws -> [String] {
        let header = try #require(usage.range(of: "\nOptions:\n"))
        let lines = usage[header.upperBound...].split(separator: "\n")
        let isOption = { (line: Substring) in line.drop { $0 == " " }.hasPrefix("--") }
        let first = try #require(lines.first(where: isOption))
        let column = first.prefix { $0 == " " }.count
        return lines
            .filter { isOption($0) && $0.prefix { $0 == " " }.count == column }
            .compactMap { $0.split(separator: " ").first.map(String.init) }
    }
}
