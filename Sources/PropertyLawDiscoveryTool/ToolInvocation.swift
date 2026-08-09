import Foundation

/// Argv-parsed invocation. Plugin → tool argv shape:
/// `--target <name> --output <path> [--advisory] [--advisory-min <level>]
///  --source-files <p1> <p2> ...`
struct ToolInvocation: Sendable {
    let target: String
    let outputPath: String
    let sourceFiles: [String]
    /// Dependency sources, read for declarations only — see
    /// `ModuleScanner.scan(sourceFiles:contextFiles:)`.
    let contextFiles: [String]
    /// Modules to `import` in the generated file beyond those the scan can
    /// infer — the opt-in path for a package that *supplies* generators, such
    /// as `PropertyLawSyntax` answering the emitted `Syntax.gen()`.
    ///
    /// Not inferred: an opt-in product's import would break the build of every
    /// project that has the type and not the dependency, turning a clear
    /// "provide a `gen()`" diagnostic into "no such module".
    let extraImports: [String]
    let advisory: Bool
    let advisoryMinConfidence: SuggestionConfidence
    /// Optional path for the opt-in scaffold file (`--scaffold-out`).
    let scaffoldOutputPath: String?

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
        self.contextFiles = builder.contextFiles
        self.extraImports = builder.extraImports
        self.advisory = builder.advisory
        self.advisoryMinConfidence = builder.advisoryMin
        self.scaffoldOutputPath = builder.scaffoldOutputPath
    }

    /// Mutable accumulator for the argv loop — keeps `init(arguments:)`
    /// under the cyclomatic-complexity / function-length lints.
    private struct Builder {
        var target: String?
        var outputPath: String?
        var sourceFiles: [String] = []
        var contextFiles: [String] = []
        var extraImports: [String] = []
        var advisory = false
        var advisoryMin: SuggestionConfidence = .high
        var scaffoldOutputPath: String?
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
        case "--scaffold-out":
            builder.scaffoldOutputPath = try requireValue(after: arg, arguments: arguments, at: index)
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
        case "--context-files":
            return consumeContextFiles(arguments: arguments, from: index + 1, into: &builder)
        case "--extra-import":
            builder.extraImports.append(
                try requireValue(after: arg, arguments: arguments, at: index)
            )
            return index + 2
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
        consumePaths(arguments: arguments, from: start) { builder.sourceFiles.append($0) }
    }

    private static func consumeContextFiles(
        arguments: [String],
        from start: Int,
        into builder: inout Builder
    ) -> Int {
        consumePaths(arguments: arguments, from: start) { builder.contextFiles.append($0) }
    }

    /// Variadic path list, terminated by the next `--flag` or end of argv.
    private static func consumePaths(
        arguments: [String],
        from start: Int,
        append: (String) -> Void
    ) -> Int {
        var index = start
        while index < arguments.count, !arguments[index].hasPrefix("--") {
            append(arguments[index])
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
