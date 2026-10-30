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
}
