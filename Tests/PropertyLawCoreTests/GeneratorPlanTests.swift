import Testing
@testable import PropertyLawCore

/// Direct coverage of the `GeneratorPlan` tree's rendering and import
/// aggregation (Phase 1 of generator scaffolding). The composite parser's
/// own tests already exercise plans end-to-end via `composedGenerator`; these
/// pin the node-level contract.
struct GeneratorPlanTests {

    private let int = GeneratorPlan.leaf(expression: "Gen<Int>.int()", imports: [])
    private let date = GeneratorPlan.leaf(expression: "Gen<Date>.date", imports: ["Foundation"])

    @Test func leafRendersItsExpression() {
        #expect(int.rendered == "Gen<Int>.int()")
        #expect(int.requiredImports == [])
    }

    @Test func collectionWrappersRender() {
        #expect(GeneratorPlan.optional(int).rendered == "Gen<Int>.int().optional")
        #expect(GeneratorPlan.array(int).rendered == "Gen<Int>.int().array(of: 0...8)")
        #expect(GeneratorPlan.set(int).rendered == "Gen<Int>.int().set(ofAtMost: 0...8)")
    }

    @Test func dictionaryZipsKeyAndValue() {
        let plan = GeneratorPlan.dictionary(key: int, value: int)
        #expect(plan.rendered == "zip(Gen<Int>.int(), Gen<Int>.int()).dictionary(ofAtMost: 0...8)")
    }

    @Test func nestingRendersInsideOut() {
        // `[Int?]` → array of optional of Int.
        let plan = GeneratorPlan.array(.optional(int))
        #expect(plan.rendered == "Gen<Int>.int().optional.array(of: 0...8)")
    }

    @Test func importsPropagateThroughWrappersAndUnionInDictionary() {
        #expect(GeneratorPlan.array(date).requiredImports == ["Foundation"])
        #expect(GeneratorPlan.optional(date).requiredImports == ["Foundation"])
        #expect(GeneratorPlan.dictionary(key: int, value: date).requiredImports == ["Foundation"])
        #expect(GeneratorPlan.dictionary(key: int, value: int).requiredImports == [])
    }
}
