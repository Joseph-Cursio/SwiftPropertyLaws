import Testing
@testable import PropertyLawDiscoveryTool

struct ToolInvocationTests {

    @Test func parsesMinimalInvocation() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--source-files", "/a/b.swift", "/a/c.swift"
        ])
        #expect(invocation.target == "MyModule")
        #expect(invocation.outputPath == "/tmp/out.swift")
        #expect(invocation.sourceFiles == ["/a/b.swift", "/a/c.swift"])
    }

    @Test func parsesEmptySourceFilesList() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--source-files"
        ])
        #expect(invocation.sourceFiles == [])
    }

    @Test func sourceFilesTerminatesAtNextFlag() throws {
        // --source-files greedily consumes positional args until the next
        // `--`-prefixed token. Order of flags shouldn't matter.
        let invocation = try ToolInvocation(arguments: [
            "--source-files", "/x.swift", "/y.swift",
            "--target", "MyModule",
            "--output", "/tmp/out.swift"
        ])
        #expect(invocation.sourceFiles == ["/x.swift", "/y.swift"])
        #expect(invocation.target == "MyModule")
    }

    @Test func missingTargetThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: ["--output", "/tmp/out.swift"])
        }
    }

    @Test func missingOutputThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: ["--target", "MyModule"])
        }
    }

    @Test func unknownArgumentThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "MyModule",
                "--output", "/tmp/out.swift",
                "--unknown-flag", "x"
            ])
        }
    }

    /// Every flag that consumes a value must reject being the last argument.
    ///
    /// `requireValue(after:arguments:at:)` is one three-line bounds check shared by five
    /// flags, and before this only two of the five reached it in a test — `--target` here
    /// and `--advisory-min` below. The other three were covered by the shape of the
    /// `switch`, not by anything asserted, so a sixth value-taking flag added without a
    /// `requireValue` call would have subscripted past the end of argv and trapped, with no
    /// test to say so.
    ///
    /// Parameterised over the flags rather than written out, because the drift this guards
    /// is a flag being *added*: a new `case` that forgets the guard has to be listed here to
    /// be considered, and a reader adding one sees the list.
    @Test(arguments: ["--target", "--output", "--scaffold-out", "--advisory-min", "--extra-import"])
    func aValueFlagAsTheLastArgumentThrowsMissingValue(flag: String) {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [flag])
        }
        // And after a complete invocation, so the failure is the trailing flag rather than
        // anything missing earlier.
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "MyModule", "--output", "/tmp/out.swift",
                "--source-files", "/a.swift", flag
            ])
        }
    }

    /// The control. Without it the law above passes against a parser that rejects every one
    /// of those flags outright.
    @Test func aValueFlagFollowedByAValueIsAccepted() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--scaffold-out", "/tmp/scaffold.swift",
            "--advisory-min", "low",
            "--extra-import", "PropertyLawSyntax",
            "--source-files", "/a.swift"
        ])
        #expect(invocation.target == "MyModule")
        #expect(invocation.outputPath == "/tmp/out.swift")
        #expect(invocation.scaffoldOutputPath == "/tmp/scaffold.swift")
        #expect(invocation.advisoryMinConfidence == .low)
        #expect(invocation.extraImports == ["PropertyLawSyntax"])
    }

    // MARK: - PRD §5.4 advisory flags (M4)

    @Test func advisoryDefaultsToOff() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--source-files", "/a.swift"
        ])
        #expect(invocation.advisory == false)
        #expect(invocation.advisoryMinConfidence == .high)
    }

    @Test func parsesAdvisoryFlag() throws {
        let invocation = try ToolInvocation(arguments: [
            "--target", "MyModule",
            "--output", "/tmp/out.swift",
            "--advisory",
            "--source-files", "/a.swift"
        ])
        #expect(invocation.advisory)
        #expect(invocation.advisoryMinConfidence == .high)
    }

    @Test func parsesAdvisoryMinConfidence() throws {
        let lowInvocation = try ToolInvocation(arguments: [
            "--target", "M", "--output", "/tmp/o.swift",
            "--advisory", "--advisory-min", "low",
            "--source-files"
        ])
        #expect(lowInvocation.advisoryMinConfidence == .low)

        let mediumInvocation = try ToolInvocation(arguments: [
            "--target", "M", "--output", "/tmp/o.swift",
            "--advisory", "--advisory-min", "medium",
            "--source-files"
        ])
        #expect(mediumInvocation.advisoryMinConfidence == .medium)
    }

    @Test func invalidAdvisoryMinThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "M", "--output", "/tmp/o.swift",
                "--advisory-min", "totally-invalid",
                "--source-files"
            ])
        }
    }

    @Test func missingValueAfterAdvisoryMinThrows() {
        #expect(throws: InvocationError.self) {
            _ = try ToolInvocation(arguments: [
                "--target", "M", "--output", "/tmp/o.swift",
                "--advisory-min"
            ])
        }
    }
}
