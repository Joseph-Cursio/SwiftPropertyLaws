@testable import PropertyLawDiscoveryTool
import Testing

/// `ToolOutput`'s two print functions: each writes to its own stream, ends
/// with a newline, and writes nothing at all for no lines. `run` never hands
/// `printLines` an empty list today, so only this test holds it to that.
struct ToolOutputTests {

    private final class Streams {
        var standardOutput: [String] = []
        var standardError: [String] = []

        var output: ToolOutput {
            ToolOutput(
                writeStandardOutput: { self.standardOutput.append($0) },
                writeStandardError: { self.standardError.append($0) }
            )
        }
    }

    @Test func linesGoToTheirOwnStreamNewlineTerminated() {
        let streams = Streams()
        streams.output.printLines(["one", "two"])
        streams.output.printErrorLines(["three"])
        #expect(streams.standardOutput == ["one\ntwo\n"])
        #expect(streams.standardError == ["three\n"])
    }

    @Test func noLinesWriteNothing() {
        let streams = Streams()
        streams.output.printLines([])
        streams.output.printErrorLines([])
        #expect(streams.standardOutput.isEmpty)
        #expect(streams.standardError.isEmpty)
    }
}
