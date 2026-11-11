/// Canonical spelling of the generated `@Test func` stub shared by the
/// `@PropertyLawSuite` macro and the discovery plugin's file emitter — the one
/// place the kit decides how a per-conformance property-law test reads. Both
/// emitters previously hand-rolled this identical shape independently.
///
/// `lines(...)` returns the stub at the discovery plugin's 4-space base
/// indentation (the form written verbatim into a generated test file). The
/// macro, whose `@Suite` template re-applies indentation when it interpolates
/// the method, strips the leading indent from the first line on its side.
package enum PropertyLawTestStub {

    /// `<testNameFragment>_<typeName>` — keeps generated tests greppable in
    /// test output. The type name goes through `QualifiedTypeName.identifier`
    /// because a nested type arrives here qualified (`BitSet.Counted`) and a
    /// dot is not legal in a function name; unqualified names are unchanged.
    package static func testName(conformance: KnownProtocol, typeName: String) -> String {
        "\(conformance.testNameFragment)_\(QualifiedTypeName.identifier(for: typeName))"
    }

    /// The six source lines of the generated test method, 4-space-indented.
    package static func lines(
        conformance: KnownProtocol,
        typeName: String,
        generatorExpr: String
    ) -> [String] {
        [
            "    @Test func \(testName(conformance: conformance, typeName: typeName))() async throws {",
            "        try await \(conformance.checkFunctionName)(",
            "            for: \(typeName).self,",
            "            using: \(indentingContinuationLines(of: generatorExpr, to: 12))",
            "        )",
            "    }",
        ]
    }

    /// Places a multi-line generator so its last line, the one that closes
    /// it, sits under the `using:` line it follows, `width` spaces in. Every
    /// continuation line moves by the same amount, so the expression keeps
    /// its own shape.
    ///
    /// The kit's expressions use two conventions, and the closing line is
    /// what tells them apart. `EnumCaseEmitter` renders a `Gen.oneOf(` list
    /// with its cases at column 4 and the closing `)` at column 0, and that
    /// list used to be spliced in at the method's left margin; now its cases
    /// sit 4 under `using:` and `)` lines up beneath it. `MemberwiseEmitter`
    /// already puts its closing `.map` line 12 spaces in, where `using:` sits,
    /// so a memberwise generator does not move.
    ///
    /// Anchoring on the least-indented line instead moved that `.map` to
    /// column 24 whenever a member was itself a multi-line `oneOf`, whose
    /// inner `)` sits at column 0. Such a generator is left as `main` emitted
    /// it, with the inner list at the margin: placing it properly would need
    /// `MemberwiseEmitter`, which is public, to stop fixing its `.map` at
    /// column 12. Empty lines stay empty rather than gaining trailing
    /// whitespace.
    static func indentingContinuationLines(of expression: String, to width: Int) -> String {
        var lines = expression.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let closing = lines.dropFirst().last(where: { !$0.isEmpty }) else {
            return expression
        }
        // Never left: a closing line already deeper than `width` stays put.
        let shift = String(repeating: " ", count: max(0, width - closing.prefix { $0 == " " }.count))
        for index in lines.indices.dropFirst() where !lines[index].isEmpty {
            lines[index] = shift + lines[index]
        }
        return lines.joined(separator: "\n")
    }
}
