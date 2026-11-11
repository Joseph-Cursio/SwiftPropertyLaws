@testable import PropertyLawCore
import Testing

/// The stub both the macro and the discovery plugin emit for one conformance.
/// What these tests pin is where a multi-line generator's continuation lines
/// land. An enum's `Gen.oneOf(` list used to be spliced in at the method's
/// left margin, and no test in this target or the plugin's noticed: only the
/// macro goldens showed it, and they pinned the wrong text.
///
/// Every expression here comes from the real emitter rather than a quoted
/// string, so a change to an emitter's layout shows up here.
struct PropertyLawTestStubTests {

    /// The stub's source lines. `lines(...)` returns six strings, the
    /// `using:` one carrying the generator's continuation lines inside it,
    /// so they are split apart here to compare one line at a time.
    private func stub(_ expression: String) -> [String] {
        PropertyLawTestStub.lines(conformance: .equatable, typeName: "Light", generatorExpr: expression)
            .joined(separator: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private func header(_ using: String) -> [String] {
        [
            "    @Test func equatable_Light() async throws {",
            "        try await checkEquatablePropertyLaws(",
            "            for: Light.self,",
            "            using: " + using,
        ]
    }

    private let footer = ["        )", "    }"]

    @Test func aSingleLineGeneratorIsUnchanged() {
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .enumCases(cases: [EnumCaseGenerator(caseName: "on")])
        )
        #expect(stub(expression) == header("Gen.always(Light.on)") + footer)
    }

    /// The cases sit 4 under `using:`, and the closing `)` lines up with it.
    @Test func anEnumsCasesSitUnderUsing() {
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .enumCases(cases: [EnumCaseGenerator(caseName: "on"), EnumCaseGenerator(caseName: "off")])
        )
        #expect(stub(expression) == header("Gen.oneOf(") + [
            "                Gen.always(Light.on).eraseToAny(),",
            "                Gen.always(Light.off).eraseToAny()",
            "            )",
        ] + footer)
    }

    /// `MemberwiseEmitter` already puts its `.map` where `using:` sits, and
    /// the stub leaves it there.
    @Test func aMemberwiseGeneratorIsUnchanged() {
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .memberwiseArbitrary(members: [
                MemberSpec(name: "a", rawType: .int),
                MemberSpec(name: "b", rawType: .bool),
            ])
        )
        let lines = expression.split(separator: "\n").map(String.init)
        #expect(lines.count == 2)
        #expect(stub(expression) == header(lines[0]) + [lines[1]] + footer)
        #expect(lines[1].hasPrefix("            .map {"))
    }

    /// A case with a payload is rendered by `MemberwiseEmitter`, `.map` and
    /// all, inside the `oneOf` list. Its `.map` stays 8 under its `zip(`.
    @Test func aPayloadCaseKeepsItsMapUnderItsZip() {
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .enumCases(cases: [
                EnumCaseGenerator(caseName: "off"),
                EnumCaseGenerator(caseName: "dimmed", arguments: [
                    InitArgument(label: "level", generatorExpression: "Gen<Int>.int()"),
                    InitArgument(label: "warm", generatorExpression: "Gen<Bool>.bool()"),
                ]),
            ])
        )
        let lines = stub(expression)
        let zipLine = lines.firstIndex { $0.contains("zip(") }
        #expect(zipLine.map { lines[$0].hasPrefix("                zip(") } == true)
        #expect(zipLine.map { lines[$0 + 1].hasPrefix("                        .map {") } == true)
        #expect(lines[lines.count - 3] == "            )")
    }

    /// A memberwise generator whose member is itself a multi-line `oneOf`
    /// ends on its `.map` line, already at column 12, so nothing moves. The
    /// inner list keeps the column-4 cases it has on `main`. Anchoring on the
    /// least-indented line, the inner `)` at column 0, would have pushed the
    /// `.map` to column 24.
    @Test func aMemberwiseGeneratorWithAMultiLineMemberDoesNotMove() {
        let member = GeneratorExpressionEmitter.expression(
            typeName: "Mode",
            strategy: .enumCases(cases: [EnumCaseGenerator(caseName: "a"), EnumCaseGenerator(caseName: "b")])
        )
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .memberwiseArbitrary(members: [
                MemberSpec(name: "level", rawType: .int),
                MemberSpec(name: "mode", generatorExpression: member),
            ])
        )
        let lines = stub(expression)
        // The expression spliced in exactly as rendered, which is what `main` emitted.
        let asRendered = (header(expression) + footer).joined(separator: "\n")
        #expect(lines.joined(separator: "\n") == asRendered)
        #expect(lines[lines.count - 3].hasPrefix("            .map {"))
    }

    /// An empty line stays empty, and a trailing one is not taken for the
    /// closing line: here `)` at column 4 closes the expression and moves to
    /// 12, and reading the trailing empty line as the closer, at column 0,
    /// would push every line 4 further in.
    @Test func emptyLinesStayEmpty() {
        #expect(
            PropertyLawTestStub.indentingContinuationLines(of: "f(\n\n        x\n    )\n", to: 12)
                == "f(\n\n                x\n            )\n"
        )
    }
}
