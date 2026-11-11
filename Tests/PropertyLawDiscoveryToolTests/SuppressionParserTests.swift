@testable import PropertyLawDiscoveryTool
import Testing

struct SuppressionParserTests {

    @Test func extractsSingleMarker() {
        let text = """
            @Suite struct FooPropertyLawTests {
                // property-law-suppress: hashable_Foo
                @Test func equatable_Foo() async throws { /* ... */ }
            }
            """
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["hashable_Foo"])
    }

    @Test func extractsMultipleMarkers() {
        let text = """
            @Suite struct FooPropertyLawTests {
                // property-law-suppress: hashable_Foo
                // property-law-suppress: codable_Foo
            }
            """
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["hashable_Foo", "codable_Foo"])
    }

    @Test func ignoresUnrelatedComments() {
        let text = """
            // some unrelated comment
            // property-law-suppress: equatable_Foo
            // FIXME: nothing
            """
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["equatable_Foo"])
    }

    @Test func toleratesLeadingWhitespace() {
        let text = "    // property-law-suppress: equatable_Foo"
        let keys = SuppressionParser.parse(text: text)
        #expect(keys == ["equatable_Foo"])
    }

    @Test func emptyMarkerKeyIsIgnored() {
        let text = "// property-law-suppress: "
        let keys = SuppressionParser.parse(text: text)
        #expect(keys.isEmpty)
    }

    @Test func nonExistentFileReturnsEmptySet() {
        let keys = SuppressionParser.parse(existingFileAt: "/nonexistent/path.swift")
        #expect(keys.isEmpty)
    }
}
