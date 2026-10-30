import Testing
@testable import PropertyLawDiscoveryTool

/// `ParsedArguments` and `PluginError` are compiled into this target through
/// symlinks into `Plugins/PropertyLawDiscoveryPlugin`, since a plugin target
/// cannot be imported.
struct PluginArgumentsTests {

    @Test func parsesEveryFlag() throws {
        let parsed = try ParsedArguments(arguments: [
            "discover",
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--scaffold-out", "/tmp/scaffold.swift",
            "--extra-import", "PropertyLawSyntax",
            "--advisory",
            "--extra-import", "OtherModule",
            "--advisory-min", "low"
        ])
        #expect(parsed.subcommand == "discover")
        #expect(parsed.target == "MyModule")
        #expect(parsed.outputPath == "/tmp/out.swift")
        #expect(parsed.scaffoldOutputPath == "/tmp/scaffold.swift")
        // Repeatable, kept in the order given rather than the last one winning.
        #expect(parsed.extraImports == ["PropertyLawSyntax", "OtherModule"])
        #expect(parsed.advisory)
        #expect(parsed.advisoryMin == "low")
    }

    @Test func flagsAreOptionalAtParseTime() throws {
        // `--target` is required, but `performCommand` says so, after the
        // subcommand check, so an unknown subcommand is reported as one.
        let parsed = try ParsedArguments(arguments: ["discover"])
        #expect(parsed.target == nil)
        #expect(parsed.outputPath == nil)
        #expect(parsed.scaffoldOutputPath == nil)
        #expect(parsed.extraImports == [])
        #expect(parsed.advisory == false)
        #expect(parsed.advisoryMin == nil)
    }

    @Test func noArgumentsThrowsMissingSubcommand() {
        #expect(throws: PluginError.missingSubcommand) {
            _ = try ParsedArguments(arguments: [])
        }
    }

    @Test func unknownArgumentThrows() {
        #expect(throws: PluginError.unknownArgument("--unknown-flag")) {
            _ = try ParsedArguments(arguments: ["discover", "--unknown-flag", "x"])
        }
    }

    /// Every flag that takes a value must reject being the last argument, and
    /// name itself in the error.
    @Test(arguments: ["--target", "--output", "--scaffold-out", "--extra-import", "--advisory-min"])
    func aValueFlagAsTheLastArgumentThrows(flag: String) {
        #expect(throws: PluginError.missingFlag(flag)) {
            _ = try ParsedArguments(arguments: ["discover", "--target", "MyModule", flag])
        }
    }

    // MARK: - The argv handed to the tool

    @Test func toolArgumentsPutThePathListsLast() throws {
        let parsed = try ParsedArguments(arguments: [
            "discover",
            "--extra-import", "A",
            "--advisory",
            "--scaffold-out", "/tmp/scaffold.swift",
            "--advisory-min", "medium",
            "--extra-import", "B"
        ])
        let arguments = parsed.toolArguments(
            target: "MyModule",
            outputPath: "/tmp/out.swift",
            sourceFiles: ["/a.swift", "/b.swift"],
            contextFiles: ["Dep=/dep.swift"]
        )
        #expect(arguments == [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--scaffold-out", "/tmp/scaffold.swift",
            "--extra-import", "A",
            "--extra-import", "B",
            "--advisory",
            "--advisory-min", "medium",
            "--source-files", "/a.swift", "/b.swift",
            "--context-files", "Dep=/dep.swift"
        ])
    }

    /// Nothing the user left out reaches the tool, which applies its own
    /// defaults.
    @Test func unsetFlagsAreNotForwarded() throws {
        let parsed = try ParsedArguments(arguments: ["discover"])
        let arguments = parsed.toolArguments(
            target: "MyModule", outputPath: "/tmp/out.swift",
            sourceFiles: ["/a.swift"], contextFiles: []
        )
        #expect(arguments == [
            "--target", "MyModule", "--output", "/tmp/out.swift", "--source-files", "/a.swift"
        ])
    }

    /// The forwarded argv read back by the tool's own parser. The plugin and
    /// the tool each parse flags in their own `switch` and share no code, so
    /// this is the one place a flag the plugin forwards in a shape the tool
    /// does not accept would show up.
    @Test func theToolReadsBackWhatThePluginForwards() throws {
        let parsed = try ParsedArguments(arguments: [
            "discover", "--target", "MyModule",
            "--scaffold-out", "/tmp/scaffold.swift",
            "--extra-import", "PropertyLawSyntax", "--extra-import", "OtherModule",
            "--advisory", "--advisory-min", "low"
        ])
        let invocation = try ToolInvocation(arguments: parsed.toolArguments(
            target: "MyModule",
            outputPath: "/tmp/out.swift",
            sourceFiles: ["/a.swift", "/b.swift"],
            contextFiles: ["Dep=/dep.swift"]
        ))
        #expect(invocation.target == "MyModule")
        #expect(invocation.outputPath == "/tmp/out.swift")
        #expect(invocation.scaffoldOutputPath == "/tmp/scaffold.swift")
        #expect(invocation.extraImports == ["PropertyLawSyntax", "OtherModule"])
        #expect(invocation.advisory)
        #expect(invocation.advisoryMinConfidence == .low)
        #expect(invocation.sourceFiles == ["/a.swift", "/b.swift"])
        #expect(invocation.contextFiles == ["Dep=/dep.swift"])
    }

    // MARK: - Parity with the tool's flags

    /// The tool flags the plugin fills in itself, from the `PluginContext`.
    static let suppliedByThePlugin: [ToolFlag] = [.sourceFiles, .contextFiles]

    /// Every other flag the tool takes must be one a user can give the plugin,
    /// and must reach the tool.
    ///
    /// The plugin parses its argv with its own `switch` of string literals,
    /// because it cannot import `ToolFlag`, so this is what holds the two lists
    /// together: a flag added to the tool fails here until the plugin forwards
    /// it. It would have failed the day `--extra-import` and `--scaffold-out`
    /// were added.
    @Test(arguments: ToolFlag.allCases.filter { !suppliedByThePlugin.contains($0) })
    func everyFlagAUserGivesTheToolPassesThroughThePlugin(flag: ToolFlag) throws {
        let parsed = try parsedAsAUserWouldPass(flag)
        let arguments = parsed.toolArguments(
            target: "MyModule", outputPath: "/tmp/out.swift", sourceFiles: [], contextFiles: []
        )
        #expect(arguments.contains(flag.rawValue))
    }

    /// Keeps the exemption above honest: a flag stays on that list only while
    /// the plugin really does refuse it from a user.
    @Test(arguments: suppliedByThePlugin)
    func theFlagsThePluginSuppliesAreNotTakenFromAUser(flag: ToolFlag) {
        #expect(throws: PluginError.unknownArgument(flag.rawValue)) {
            _ = try ParsedArguments(arguments: ["discover", flag.rawValue, "/a.swift"])
        }
    }

    /// The plugin's argv for `flag` alone, with a value after it if it takes
    /// one. Only the plugin's parser knows which flags do, so this passes a
    /// value and drops it again if the value is what was rejected.
    private func parsedAsAUserWouldPass(_ flag: ToolFlag) throws -> ParsedArguments {
        do {
            return try ParsedArguments(arguments: ["discover", flag.rawValue, "value"])
        } catch PluginError.unknownArgument("value") {
            return try ParsedArguments(arguments: ["discover", flag.rawValue])
        }
    }
}
