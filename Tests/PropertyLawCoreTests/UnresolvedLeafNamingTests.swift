import Testing
@testable import PropertyLawCore

/// A composite spelling fails because of a leaf inside it, and the `.todo`
/// reason names that leaf — `Widget`, not `[String: [Widget]]`.
struct UnresolvedLeafNamingTests {

    private func leaf(
        _ typeName: String,
        resolve: @escaping DerivationStrategist.CustomTypeResolver = { _ in nil }
    ) -> String? {
        DerivationStrategist.firstUnresolvedLeaf(inTypeName: typeName, resolve: resolve)
    }

    // MARK: - The walk

    @Test("each composite form is looked inside", arguments: [
        "[Widget]", "Widget?", "Optional<Widget>", "Array<Widget>", "ArraySlice<Widget>",
        "Set<Widget>", "[String: [Widget]]", "[Widget: Int]", "Dictionary<Int, Set<Widget>>",
        "[[Widget?]]", " [ Widget ] "
    ])
    func compositeFormsReachTheLeaf(typeName: String) {
        #expect(leaf(typeName) == "Widget")
    }

    @Test("a spelling that resolves has no unresolved leaf")
    func resolvedSpellingHasNoLeaf() {
        #expect(leaf("[String: [Int?]]") == nil)
        #expect(leaf("Date") == nil)
    }

    @Test("a bare unresolved type is its own leaf")
    func bareTypeIsItsOwnLeaf() {
        #expect(leaf("Widget") == "Widget")
    }

    /// Not a form the parser decomposes, so it is reported whole rather than
    /// guessed at.
    @Test("an undecomposed generic is reported whole")
    func unknownGenericIsReportedWhole() {
        #expect(leaf("[Box<Widget>]") == "Box<Widget>")
    }

    /// The resolved key must be passed over, and a key that fails must be
    /// found before a value that also fails.
    @Test("the resolver is consulted and components are searched in order")
    func consultsResolverInOrder() {
        let known = DerivationStrategist.ComposedGenerator(expression: "Good.gen()")
        let resolve: DerivationStrategist.CustomTypeResolver = { $0 == "Good" ? known : nil }
        #expect(leaf("[Good: Bad]", resolve: resolve) == "Bad")
        #expect(leaf("[Good]", resolve: resolve) == nil)
        #expect(leaf("[First: Second]") == "First")
    }

    // MARK: - The messages

    private func todo(_ shape: TypeShape) -> String? {
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else { return nil }
        return reason
    }

    @Test("a composite stored property names its leaf")
    func memberMessageNamesLeaf() throws {
        let text = try #require(todo(TypeShape(
            name: "Doc", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "links", typeName: "[String: [Widget]]")]
        )))
        #expect(text.contains(
            "`links: [String: [Widget]]` resolves to no generator — `Widget`, inside `[String: [Widget]]`, is not"
        ))
    }

    @Test("a bare stored property reads as before")
    func bareMemberMessageUnchanged() throws {
        let text = try #require(todo(TypeShape(
            name: "Doc", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "widget", typeName: "Widget")]
        )))
        #expect(text.contains("`widget: Widget` resolves to no generator — `Widget` is not"))
        #expect(!text.contains("inside"))
    }

    @Test("a composite init parameter names its leaf")
    func initMessageNamesLeaf() throws {
        let text = try #require(todo(TypeShape(
            name: "Doc", kind: .struct, inheritedTypes: ["Equatable"], hasUserGen: false,
            storedMembers: [StoredMember(name: "links", typeName: "Int")],
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: [
                InitializerParameter(label: "links", typeName: "Set<Widget>")
            ])]
        )))
        #expect(text.contains(
            "`init(links:)` takes `links: Set<Widget>`, which resolves to no generator because `Widget` does not."
        ))
    }

    @Test("a composite enum payload names its leaf")
    func enumMessageNamesLeaf() throws {
        let text = try #require(todo(TypeShape(
            name: "Event", kind: .enum, inheritedTypes: ["Equatable"], hasUserGen: false,
            enumCases: [EnumCase(name: "batch", associatedValues: [
                InitializerParameter(label: nil, typeName: "[Widget]")
            ])]
        )))
        #expect(text.contains(
            "of type `[Widget]`, which resolves to no generator because `Widget` does not."
        ))
    }
}
