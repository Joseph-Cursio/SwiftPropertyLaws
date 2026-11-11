import Foundation

/// Where `PropertyLawDiscoveryTool.run(arguments:output:)` writes what it
/// reports: the usage text and the summary on standard output, the advisory
/// notes on standard error.
///
/// `main()` passes the process's own streams. A test passes closures that
/// collect the text, so the summary and the advisory notes can be read
/// without spawning the tool. Nothing called `main()` before this existed,
/// so none of that text was checked.
struct ToolOutput {
    let writeStandardOutput: (String) -> Void
    let writeStandardError: (String) -> Void

    /// The process's standard output and standard error.
    static var standard: Self {
        Self(
            writeStandardOutput: { FileHandle.standardOutput.write(Data($0.utf8)) },
            writeStandardError: { FileHandle.standardError.write(Data($0.utf8)) }
        )
    }

    /// Writes each line to standard output, newline-terminated. No lines
    /// write nothing, not an empty line.
    func printLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        writeStandardOutput(lines.joined(separator: "\n") + "\n")
    }

    /// Writes each line to standard error, newline-terminated. No lines
    /// write nothing, not an empty line.
    func printErrorLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        writeStandardError(lines.joined(separator: "\n") + "\n")
    }
}
