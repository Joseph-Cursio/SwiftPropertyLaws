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

    /// A memberwise generator's `.map` sits at column 0 of the expression,
    /// and the stub moves it 12, under `using:`, where `main` emitted it.
    @Test func aMemberwiseGeneratorsMapSitsUnderUsing() {
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .memberwiseArbitrary(members: [
                MemberSpec(name: "a", rawType: .int),
                MemberSpec(name: "b", rawType: .bool),
            ])
        )
        #expect(expression == "zip(Gen<Int>.int(), Gen<Bool>.bool())\n.map { Light(a: $0.0, b: $0.1) }")
        #expect(stub(expression) == header("zip(Gen<Int>.int(), Gen<Bool>.bool())") + [
            "            .map { Light(a: $0.0, b: $0.1) }",
        ] + footer)
    }

    /// A case with a payload is rendered by `MemberwiseEmitter`, `.map` and
    /// all, inside the `oneOf` list. The list moves its `.map` 4 with the
    /// case, so it sits under its `zip(`.
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
        #expect(stub(expression) == header("Gen.oneOf(") + [
            "                Gen.always(Light.off).eraseToAny(),",
            "                zip(Gen<Int>.int(), Gen<Bool>.bool())",
            "                .map { Light.dimmed(level: $0.0, warm: $0.1) }.eraseToAny()",
            "            )",
        ] + footer)
    }

    /// A memberwise generator whose member is a multi-line `oneOf`: the inner
    /// list starts on the `zip(` line, so its cases sit 4 under `using:` and
    /// its `)` under `using:`, and the `.map` stays under `using:` too. `main`
    /// left the inner list at the method's left margin, because the `.map`
    /// came out of `MemberwiseEmitter` already 12 in.
    @Test func aMultiLineMemberOfAMemberwiseGeneratorSitsUnderUsing() {
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
        #expect(stub(expression) == header("zip(Gen<Int>.int(), Gen.oneOf(") + [
            "                Gen.always(Mode.a).eraseToAny(),",
            "                Gen.always(Mode.b).eraseToAny()",
            "            ))",
            "            .map { Light(level: $0.0, mode: $0.1) }",
        ] + footer)
    }

    /// Three levels: a payload case whose member is a multi-line `oneOf`,
    /// inside an enum's list. Each level adds only its own column, so the
    /// innermost cases sit 8 under `using:`.
    @Test func eachLevelAddsOnlyItsOwnColumn() {
        let mode = GeneratorExpressionEmitter.expression(
            typeName: "Mode",
            strategy: .enumCases(cases: [EnumCaseGenerator(caseName: "a"), EnumCaseGenerator(caseName: "b")])
        )
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Light",
            strategy: .enumCases(cases: [
                EnumCaseGenerator(caseName: "off"),
                EnumCaseGenerator(caseName: "set", arguments: [
                    InitArgument(label: "level", generatorExpression: "Gen<Int>.int()"),
                    InitArgument(label: "mode", generatorExpression: mode),
                ]),
            ])
        )
        #expect(stub(expression) == header("Gen.oneOf(") + [
            "                Gen.always(Light.off).eraseToAny(),",
            "                zip(Gen<Int>.int(), Gen.oneOf(",
            "                    Gen.always(Mode.a).eraseToAny(),",
            "                    Gen.always(Mode.b).eraseToAny()",
            "                ))",
            "                .map { Light.set(level: $0.0, mode: $0.1) }.eraseToAny()",
            "            )",
        ] + footer)
    }

    /// An empty line stays empty rather than gaining trailing whitespace,
    /// and every other continuation line moves by the same 12.
    @Test func emptyLinesStayEmpty() {
        #expect(
            ExpressionLayout.indentingContinuationLines(of: "f(\n\n    x\n)\n", by: 12)
                == "f(\n\n                x\n            )\n"
        )
    }
}
