/// Free of `PackagePlugin` for the same reason as `ParsedArguments`, which
/// throws it: `Tests/PropertyLawDiscoveryPluginTests` compiles this file too.
enum PluginError: Error, Equatable, CustomStringConvertible {
    case missingSubcommand
    case unknownSubcommand(String)
    case missingFlag(String)
    case unknownArgument(String)
    case unknownTarget(String)
    case toolFailed(status: Int32)

    var description: String {
        switch self {
        case .missingSubcommand:
            return "missing subcommand. Try: swift package propertylawcheck discover --target <name>"
        case .unknownSubcommand(let name):
            return "unknown subcommand: \(name). Available: discover"
        case .missingFlag(let flag):
            return "missing required flag \(flag)"
        case .unknownArgument(let arg):
            return "unknown argument: \(arg)"
        case .unknownTarget(let name):
            return "no target named \(name) in this package"
        case .toolFailed(let status):
            return "PropertyLawDiscoveryTool exited with status \(status)"
        }
    }
}
