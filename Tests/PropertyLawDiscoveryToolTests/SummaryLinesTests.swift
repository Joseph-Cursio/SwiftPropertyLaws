import PropertyLawCore
@testable import PropertyLawDiscoveryTool
import Testing

/// The text the tool prints, rendered without running it. Every assertion
/// compares whole lines, because each optional section is guarded by a
/// condition and a `contains` check passes whether or not the guard works.
struct SummaryLinesTests {

    private func invocation(sourceFiles: [String] = ["/a.swift", "/b.swift"]) throws -> ToolInvocation {
        try ToolInvocation(
            arguments: ["--target", "Module", "--output", "/out.swift", "--source-files"] + sourceFiles
        )
    }

    private func entry(_ name: String, todo: Bool) -> ConformanceMap.Entry {
        ConformanceMap.Entry(
            typeName: name,
            conformances: [.equatable],
            provenances: [],
            derivationStrategy: todo ? .todo(reason: "test fixture") : .userGen
        )
    }

    // MARK: - Summary

    /// With nothing to report, the summary is the four fixed lines and none
    /// of the optional sections — not even with a count of zero.
    @Test func anEmptyScanPrintsOnlyTheFixedLines() throws {
        let lines = PropertyLawDiscoveryTool.summaryLines(
            invocation: try invocation(),
            map: ConformanceMap(entries: [], parseFailures: []),
            suppressions: []
        )
        #expect(lines == [
            "PropertyLawDiscoveryTool: wrote /out.swift",
            "  target: Module",
            "  source files scanned: 2",
            "  types detected: 0",
        ])
    }

    @Test func everyOptionalSectionAppearsWhenItHasSomethingToSay() throws {
        let map = ConformanceMap(
            entries: [entry("Derived", todo: false), entry("Alpha", todo: true), entry("Beta", todo: true)],
            parseFailures: [ConformanceMap.ParseFailure(filePath: "/c.swift", message: "unreadable")],
            skippedTypes: [SkippedType(typeName: "Hidden", reason: .notNameable(.private))]
        )
        let lines = PropertyLawDiscoveryTool.summaryLines(
            invocation: try invocation(),
            map: map,
            suppressions: ["equatable_Alpha", "hashable_Beta"]
        )
        #expect(lines == [
            "PropertyLawDiscoveryTool: wrote /out.swift",
            "  target: Module",
            "  source files scanned: 2",
            "  types detected: 3",
            "  parse failures: 1",
            "  suppressions preserved: 2",
            "  detected but skipped, no suite emitted (1):",
            "    - Hidden: declared `private` — not nameable from another file",
            "  types needing manual gen() (2):",
            "    [2] other",
            "      - Alpha",
            "      - Beta",
        ])
    }

    /// Type names are listed up to 25 `.todo` types and left out above that,
    /// so a large scan's summary stays readable. The count and buckets stay.
    @Test("todo names are listed up to 25 and omitted beyond", arguments: [25, 26])
    func todoNamesAreListedOnlyForSmallScans(count: Int) throws {
        let names = (1 ... count).map { "T\($0)" }
        let lines = PropertyLawDiscoveryTool.summaryLines(
            invocation: try invocation(),
            map: ConformanceMap(entries: names.map { entry($0, todo: true) }, parseFailures: []),
            suppressions: []
        )
        let header = [
            "PropertyLawDiscoveryTool: wrote /out.swift",
            "  target: Module",
            "  source files scanned: 2",
            "  types detected: \(count)",
            "  types needing manual gen() (\(count)):",
            "    [\(count)] other",
        ]
        let listed = count <= 25 ? names.map { "      - \($0)" } : []
        #expect(lines == header + listed)
    }

    // MARK: - Advisory notes

    @Test func noSuggestionsRenderNoLines() {
        #expect(PropertyLawDiscoveryTool.advisoryLines([]).isEmpty)
        #expect(PropertyLawDiscoveryTool.roundTripLines([]).isEmpty)
    }

    @Test func anAdvisorySuggestionRendersAsANote() {
        let suggestion = Suggestion(
            typeName: "Money",
            suggestedProtocol: .equatable,
            confidence: .high,
            evidence: "declares `static func ==`"
        )
        #expect(PropertyLawDiscoveryTool.advisoryLines([suggestion]) == [
            "PropertyLawDiscoveryTool: 1 advisory suggestion(s):",
            "  note: Money declares `static func ==` but does not declare Equatable.",
            "        Consider conforming and running checkEquatablePropertyLaws "
                + "to verify the laws hold.",
            "        confidence: high",
        ])
    }

    /// A member pair is named through its type; a pair of free functions
    /// through `<module>`.
    @Test func roundTripCandidatesNameTheirScope() {
        func signature(_ name: String, _ parameter: String, _ result: String) -> FunctionSignature {
            FunctionSignature(name: name, parameterTypes: [parameter], returnType: result, isStatic: true, group: nil)
        }
        let member = RoundTripSuggestion(
            scope: .type("Codec"),
            forward: signature("encode", "Money", "String"),
            backward: signature("decode", "String", "Money"),
            confidence: .high,
            evidence: "curated name pair"
        )
        let free = RoundTripSuggestion(
            scope: .module,
            forward: signature("serialize", "Money", "String"),
            backward: signature("deserialize", "String", "Money"),
            confidence: .medium,
            evidence: "signature inversion"
        )
        #expect(PropertyLawDiscoveryTool.roundTripLines([member, free]) == [
            "PropertyLawDiscoveryTool: 2 round-trip pair candidate(s):",
            "  note: Codec.encode(_:) and Codec.decode(_:) form a round-trip pair candidate.",
            "        Consider writing a property that asserts decode(encode(x)) == x for all x.",
            "        confidence: high",
            "        evidence: curated name pair",
            "  note: <module>.serialize(_:) and <module>.deserialize(_:) form a round-trip pair candidate.",
            "        Consider writing a property that asserts deserialize(serialize(x)) == x for all x.",
            "        confidence: medium",
            "        evidence: signature inversion",
        ])
    }
}
