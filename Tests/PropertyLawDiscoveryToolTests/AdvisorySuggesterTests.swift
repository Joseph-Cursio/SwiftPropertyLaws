import Testing
@testable import PropertyLawDiscoveryTool
@testable import PropertyLawCore

/// Unit tests for `AdvisorySuggester` (PRD §5.4 missing-conformance
/// suggestions). Operates on synthetic `ConformanceMap`s — the
/// integration with `ModuleScanner.find` lives in
/// `ModuleScannerTests`.
struct AdvisorySuggesterTests {

    // MARK: - Codable

    @Test func suggestsCodableWhenBothHalvesPresentAndUndeclared() throws {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(
                hasEncodeToMethod: true,
                hasInitFromInitializer: true
            )]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions.first?.suggestedProtocol == .codable)
        #expect(suggestions.first?.confidence == .high)
    }

    @Test func skipsCodableWhenAlreadyDeclared() {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [.codable])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(
                hasEncodeToMethod: true,
                hasInitFromInitializer: true
            )]
        )
        #expect(AdvisorySuggester.suggest(from: map).isEmpty)
    }

    @Test func skipsCodableWhenOnlyOneHalfPresent() {
        let onlyEncode = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasEncodeToMethod: true)]
        )
        #expect(AdvisorySuggester.suggest(from: onlyEncode).isEmpty)

        let onlyDecode = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasInitFromInitializer: true)]
        )
        #expect(AdvisorySuggester.suggest(from: onlyDecode).isEmpty)
    }

    // MARK: - Equatable

    @Test func suggestsEquatableFromEqualEqualOperator() throws {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasEqualEqualOperator: true)]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions.first?.suggestedProtocol == .equatable)
    }

    @Test func skipsEquatableWhenAlreadyDeclared() {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [.equatable])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasEqualEqualOperator: true)]
        )
        #expect(AdvisorySuggester.suggest(from: map).isEmpty)
    }

    @Test func skipsEquatableWhenHashableAlreadyDeclared() {
        // Hashable subsumes Equatable in the stdlib hierarchy — declaring
        // Hashable means the user already has Equatable.
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [.hashable])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasEqualEqualOperator: true)]
        )
        #expect(AdvisorySuggester.suggest(from: map).isEmpty)
    }

    @Test func skipsEquatableWhenComparableAlreadyDeclared() {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [.comparable])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasEqualEqualOperator: true)]
        )
        #expect(AdvisorySuggester.suggest(from: map).isEmpty)
    }

    // MARK: - Hashable

    @Test func suggestsHashableFromHashIntoMethod() throws {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasHashIntoMethod: true)]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions.first?.suggestedProtocol == .hashable)
    }

    @Test func skipsHashableWhenAlreadyDeclared() {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [.hashable])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasHashIntoMethod: true)]
        )
        #expect(AdvisorySuggester.suggest(from: map).isEmpty)
    }

    // MARK: - Comparable

    @Test func suggestsComparableFromLessThanOperator() throws {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasLessThanOperator: true)]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions.first?.suggestedProtocol == .comparable)
    }

    // MARK: - Hierarchy dedupe

    @Test func dropsEquatableWhenHashableAlsoSuggested() throws {
        // Type with both witnesses, no conformances declared — would
        // otherwise emit two suggestions. Hashable subsumes Equatable.
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(
                hasEqualEqualOperator: true,
                hasHashIntoMethod: true
            )]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions.first?.suggestedProtocol == .hashable)
    }

    @Test func dropsEquatableWhenComparableAlsoSuggested() throws {
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(
                hasEqualEqualOperator: true,
                hasLessThanOperator: true
            )]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        try #require(suggestions.count == 1)
        #expect(suggestions.first?.suggestedProtocol == .comparable)
    }

    @Test func keepsHashableAndComparableTogether() {
        // These are orthogonal — neither subsumes the other.
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(
                hasHashIntoMethod: true,
                hasLessThanOperator: true
            )]
        )
        let suggestions = AdvisorySuggester.suggest(from: map)
        let suggested = Set(suggestions.map(\.suggestedProtocol))
        #expect(suggested == [.hashable, .comparable])
    }

    // MARK: - Confidence floor

    @Test func defaultsToHighConfidenceFloor() {
        // Sanity: M4 only emits .high, so the default floor (.high) lets
        // every suggestion through. Lowering it doesn't currently add
        // more — but it must never DROP high-confidence ones.
        let map = ConformanceMap(
            entries: [makeEntry(typeName: "Foo", conformances: [])],
            parseFailures: [],
            witnesses: ["Foo": WitnessSet(hasEqualEqualOperator: true)]
        )
        #expect(AdvisorySuggester.suggest(from: map, minConfidence: .low).count == 1)
        #expect(AdvisorySuggester.suggest(from: map, minConfidence: .medium).count == 1)
        #expect(AdvisorySuggester.suggest(from: map, minConfidence: .high).count == 1)
    }

    // MARK: - Determinism

    @Test func suggestionsAreSortedByTypeNameThenProtocol() {
        // Output must not depend on dictionary iteration order. The fixture
        // makes every other order differ: Apple's protocol sorts after
        // Banana's, so a sort by protocol alone reverses them, and Cherry has
        // two suggestions, which the detectors produce Hashable first.
        let map = ConformanceMap(
            entries: [
                makeEntry(typeName: "Cherry", conformances: []),
                makeEntry(typeName: "Banana", conformances: []),
                makeEntry(typeName: "Apple", conformances: [])
            ],
            parseFailures: [],
            witnesses: [
                "Cherry": WitnessSet(hasHashIntoMethod: true, hasLessThanOperator: true),
                "Banana": WitnessSet(hasLessThanOperator: true),
                "Apple": WitnessSet(hasEqualEqualOperator: true)
            ]
        )
        let order = AdvisorySuggester.suggest(from: map).map { "\($0.typeName).\($0.suggestedProtocol)" }
        #expect(order == ["Apple.equatable", "Banana.comparable", "Cherry.comparable", "Cherry.hashable"])
    }

    // MARK: - Empty input

    @Test func emptyMapProducesNoSuggestions() {
        let map = ConformanceMap(entries: [], parseFailures: [], witnesses: [:])
        #expect(AdvisorySuggester.suggest(from: map).isEmpty)
    }

    // MARK: - Helpers

    private func makeEntry(
        typeName: String,
        conformances: Set<KnownProtocol>
    ) -> ConformanceMap.Entry {
        ConformanceMap.Entry(
            typeName: typeName,
            conformances: conformances,
            provenances: [],
            derivationStrategy: .todo(reason: "test fixture")
        )
    }
}
