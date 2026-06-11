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
    /// test output.
    package static func testName(conformance: KnownProtocol, typeName: String) -> String {
        "\(conformance.testNameFragment)_\(typeName)"
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
            "            using: \(generatorExpr)",
            "        )",
            "    }"
        ]
    }
}
