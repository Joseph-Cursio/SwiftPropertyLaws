import Testing
@testable import PropertyLawDiscoveryTool
@testable import PropertyLawCore

/// The generated file imports what its derived generators reference: a
/// `Date` member pulls in `import Foundation`; a stdlib-only target does
/// not (so pre-Tier-2 generated files stay byte-identical).
struct ImportEmissionTests {

    private func entry(
        _ typeName: String,
        strategy: DerivationStrategy
    ) -> ConformanceMap.Entry {
        ConformanceMap.Entry(
            typeName: typeName,
            conformances: [.equatable],
            provenances: [ConformanceMap.Provenance(filePath: "/p/\(typeName).swift", line: 1, kind: .primary)],
            derivationStrategy: strategy
        )
    }

    private func strategy(for members: [StoredMember]) -> DerivationStrategy {
        DerivationStrategist.strategy(for: TypeShape(
            name: "T",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members
        ))
    }

    @Test func dateMemberAddsFoundationImport() {
        let dateStrategy = strategy(for: [StoredMember(name: "at", typeName: "Date")])
        let map = ConformanceMap(entries: [entry("Event", strategy: dateStrategy)], parseFailures: [])
        let output = GeneratedFileEmitter.emit(target: "M", map: map)
        #expect(output.contains("\nimport Foundation\n"))
        // Ordering: Foundation after the fixed kit imports.
        let kitRange = output.range(of: "import PropertyLawKit")
        let foundationRange = output.range(of: "import Foundation")
        #expect((kitRange?.upperBound ?? output.endIndex) < (foundationRange?.lowerBound ?? output.startIndex))
    }

    @Test func stdlibOnlyTargetEmitsNoExtraImports() {
        let intStrategy = strategy(for: [StoredMember(name: "x", typeName: "Int")])
        let map = ConformanceMap(entries: [entry("Point", strategy: intStrategy)], parseFailures: [])
        let output = GeneratedFileEmitter.emit(target: "M", map: map)
        #expect(output.contains("import Foundation") == false)
    }
}
