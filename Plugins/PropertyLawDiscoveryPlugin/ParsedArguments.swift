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
    /// `--scaffold-out`, forwarded as given.
    let scaffoldOutputPath: String?
    /// `--extra-import`, repeatable, in the order given. The tool drops the
    /// target's own module, so the plugin forwards every one.
    let extraImports: [String]
    let advisory: Bool
    let advisoryMin: String?

    init(arguments: [String]) throws {
        guard let command = arguments.first else {
            throw PluginError.missingSubcommand
        }
        var targetValue: String?
        var outputValue: String?
        var scaffoldValue: String?
        var importValues: [String] = []
        var advisoryFlag = false
        var advisoryMinValue: String?
        var rest = arguments.dropFirst().makeIterator()
        while let flag = rest.next() {
            switch flag {
            case "--target":
                targetValue = try Self.value(of: flag, from: &rest)

            case "--output":
                outputValue = try Self.value(of: flag, from: &rest)

            case "--scaffold-out":
                scaffoldValue = try Self.value(of: flag, from: &rest)

            case "--extra-import":
                importValues.append(try Self.value(of: flag, from: &rest))

            case "--advisory":
                advisoryFlag = true

            case "--advisory-min":
                advisoryMinValue = try Self.value(of: flag, from: &rest)

            default:
                throw PluginError.unknownArgument(flag)
            }
        }
        self.subcommand = command
        self.target = targetValue
        self.outputPath = outputValue
        self.scaffoldOutputPath = scaffoldValue
        self.extraImports = importValues
        self.advisory = advisoryFlag
        self.advisoryMin = advisoryMinValue
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
        if let scaffoldOutputPath {
            arguments.append(contentsOf: ["--scaffold-out", scaffoldOutputPath])
        }
        for module in extraImports {
            arguments.append(contentsOf: ["--extra-import", module])
        }
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
