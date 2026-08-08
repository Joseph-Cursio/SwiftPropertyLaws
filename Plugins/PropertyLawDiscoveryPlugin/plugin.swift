import PackagePlugin

/// `swift package propertylawcheck discover --target <name>` entry point.
///
/// Walks the named target's source files and forwards them to
/// `PropertyLawDiscoveryTool`, which emits a generated test file at the
/// configured output path.
///
/// Commit 1 ships the plugin scaffold + tool invocation pipeline. The
/// CLI parsing here is intentionally minimal — enough to confirm the
/// plugin → tool argv path works. Commit 5 fleshes out the
/// target-source-file gathering and output handling.
@main
struct PropertyLawDiscoveryPlugin: CommandPlugin {

    func performCommand(context: PluginContext, arguments: [String]) async throws {
        let parsed = try parse(arguments: arguments)

        guard parsed.subcommand == "discover" else {
            throw PluginError.unknownSubcommand(parsed.subcommand)
        }

        guard let target = parsed.target else {
            throw PluginError.missingFlag("--target")
        }

        let resolvedTarget = try context.package.targets(named: [target]).first
            ?? { throw PluginError.unknownTarget(target) }()
        let sourceFiles = sourceFilePaths(in: resolvedTarget)

        let outputPath = parsed.outputPath
            ?? defaultOutputPath(for: resolvedTarget, in: context)

        let tool = try context.tool(named: "PropertyLawDiscoveryTool")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool.path.string)
        var toolArgs: [String] = [
            "--target", target,
            "--output", outputPath
        ]
        if parsed.advisory { toolArgs.append("--advisory") }
        if let minLevel = parsed.advisoryMin {
            toolArgs.append(contentsOf: ["--advisory-min", minLevel])
        }
        toolArgs.append("--source-files")
        toolArgs.append(contentsOf: sourceFiles)
        // Dependency sources, for declarations only. Without them a type this
        // target merely *extends* is invisible — no members, no initializers,
        // not even its kind — and its diagnostic can only say so. Measured on
        // swift-syntax: `SwiftParser` had 114 such types scanned alone and 9
        // with its dependencies as context.
        let contextFiles = dependencySourceFilePaths(of: resolvedTarget)
        if !contextFiles.isEmpty {
            toolArgs.append("--context-files")
            toolArgs.append(contentsOf: contextFiles)
        }
        process.arguments = toolArgs
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        if status != 0 {
            throw PluginError.toolFailed(status: status)
        }
    }

    /// Default output: `Tests/<Target>Tests/PropertyLawTests.generated.swift`.
    /// Falls back to the package root if the conventional tests dir
    /// doesn't exist; commit 5 will create the dir if missing.
    private func defaultOutputPath(for target: Target, in context: PluginContext) -> String {
        let testsDir = context.package.directory
            .appending(["Tests", "\(target.name)Tests"])
        return testsDir.appending(["PropertyLawTests.generated.swift"]).string
    }

    /// Every source file of every target this one depends on, transitively.
    ///
    /// Deduplicated and sorted: a diamond in the dependency graph would
    /// otherwise hand the same file to the scanner twice, and the tool's
    /// regeneration-as-diff guarantee needs a stable order.
    ///
    /// **This costs real time** — the scanner parses each context file. Measured
    /// on `SwiftParser` (46 target files, 102 context files): 3.1s → 17.9s.
    /// Discovery is an on-demand pass rather than a build step, so the trade is
    /// accurate diagnostics and more derivations for a slower explicit run.
    private func dependencySourceFilePaths(of target: Target) -> [String] {
        var seen: Set<String> = [target.name]
        var files: Set<String> = []

        func visit(_ dependencies: [TargetDependency]) {
            for dependency in dependencies {
                switch dependency {
                case .target(let dependencyTarget):
                    guard seen.insert(dependencyTarget.name).inserted else { continue }
                    files.formUnion(attributed(dependencyTarget))
                    visit(dependencyTarget.dependencies)
                case .product(let product):
                    for productTarget in product.targets {
                        guard seen.insert(productTarget.name).inserted else { continue }
                        files.formUnion(attributed(productTarget))
                        visit(productTarget.dependencies)
                    }
                @unknown default:
                    continue
                }
            }
        }
        visit(target.dependencies)
        return files.sorted()
    }

    /// `Module=path` entries, so the tool can tell the emitter which module to
    /// `import` for a type this target only extends. A bare path would leave
    /// the emitter naming a foreign type it never imported — the same defect
    /// the `@testable import <Target>` line was added to fix, one module over.
    private func attributed(_ target: Target) -> [String] {
        sourceFilePaths(in: target).map { "\(target.name)=\($0)" }
    }

    private func sourceFilePaths(in target: Target) -> [String] {
        guard let sourceModuleTarget = target as? SourceModuleTarget else { return [] }
        return sourceModuleTarget.sourceFiles
            .filter { $0.path.extension == "swift" }
            .map { $0.path.string }
            .sorted()
    }

    /// Subcommand + flags parsed from the plugin's invocation argv.
    private struct ParsedArguments {
        let subcommand: String
        let target: String?
        let outputPath: String?
        let advisory: Bool
        let advisoryMin: String?
    }

    private func parse(arguments: [String]) throws -> ParsedArguments {
        guard let subcommand = arguments.first else {
            throw PluginError.missingSubcommand
        }
        let rest = Array(arguments.dropFirst())
        var target: String?
        var outputPath: String?
        var advisory = false
        var advisoryMin: String?
        var index = 0
        while index < rest.count {
            switch rest[index] {
            case "--target":
                index += 1
                guard index < rest.count else { throw PluginError.missingFlag("--target") }
                target = rest[index]
            case "--output":
                index += 1
                guard index < rest.count else { throw PluginError.missingFlag("--output") }
                outputPath = rest[index]
            case "--advisory":
                advisory = true
            case "--advisory-min":
                index += 1
                guard index < rest.count else {
                    throw PluginError.missingFlag("--advisory-min")
                }
                advisoryMin = rest[index]
            default:
                throw PluginError.unknownArgument(rest[index])
            }
            index += 1
        }
        return ParsedArguments(
            subcommand: subcommand,
            target: target,
            outputPath: outputPath,
            advisory: advisory,
            advisoryMin: advisoryMin
        )
    }
}

import Foundation

enum PluginError: Error, CustomStringConvertible {
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
