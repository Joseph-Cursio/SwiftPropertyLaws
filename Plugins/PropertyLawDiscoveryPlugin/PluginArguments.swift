/// Subcommand + flags parsed from the plugin's invocation argv, and the argv
/// the plugin hands `PropertyLawDiscoveryTool` in return.
///
/// **No `import PackagePlugin`, deliberately.** A plugin target cannot be a
/// test target's dependency, so the only way to test this parser is to compile
/// the file a second time: `Tests/PropertyLawDiscoveryPluginTests` reaches it
/// through a symlink. Anything here that needed `PackagePlugin` would break
/// that build, not this one.
struct ParsedArguments: Equatable {
    let subcommand: String
    let target: String?
    let outputPath: String?
    let advisory: Bool
    let advisoryMin: String?

    init(arguments: [String]) throws {
        guard let subcommand = arguments.first else {
            throw PluginError.missingSubcommand
        }
        var target: String?
        var outputPath: String?
        var advisory = false
        var advisoryMin: String?
        var rest = arguments.dropFirst().makeIterator()
        while let flag = rest.next() {
            switch flag {
            case "--target":
                target = try Self.value(of: flag, from: &rest)
            case "--output":
                outputPath = try Self.value(of: flag, from: &rest)
            case "--advisory":
                advisory = true
            case "--advisory-min":
                advisoryMin = try Self.value(of: flag, from: &rest)
            default:
                throw PluginError.unknownArgument(flag)
            }
        }
        self.subcommand = subcommand
        self.target = target
        self.outputPath = outputPath
        self.advisory = advisory
        self.advisoryMin = advisoryMin
    }

    /// The tool's argv. `sourceFiles` and `contextFiles` come from the
    /// `PluginContext`, not the user, which is why they are parameters here
    /// rather than flags above.
    ///
    /// The variadic path lists go last: the tool reads each one up to the next
    /// `--`-prefixed argument, so nothing else may sit between a list and its
    /// paths.
    func toolArguments(
        target: String,
        outputPath: String,
        sourceFiles: [String],
        contextFiles: [String]
    ) -> [String] {
        var arguments = ["--target", target, "--output", outputPath]
        if advisory { arguments.append("--advisory") }
        if let advisoryMin {
            arguments.append(contentsOf: ["--advisory-min", advisoryMin])
        }
        arguments.append("--source-files")
        arguments.append(contentsOf: sourceFiles)
        if !contextFiles.isEmpty {
            arguments.append("--context-files")
            arguments.append(contentsOf: contextFiles)
        }
        return arguments
    }

    private static func value(
        of flag: String,
        from rest: inout IndexingIterator<ArraySlice<String>>
    ) throws -> String {
        guard let value = rest.next() else {
            throw PluginError.missingFlag(flag)
        }
        return value
    }
}
