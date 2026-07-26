import Testing
@testable import PropertyLawDiscoveryTool
@testable import PropertyLawCore

// swiftlint:disable type_body_length

struct EmitterGoldenTests {

    /// Convenience builder. Most existing emitter tests want `.userGen`
    /// (the M1 default — emitter spells `<TypeName>.gen()`); the new M3
    /// tests at the bottom override the strategy explicitly.
    private func entry(
        _ typeName: String,
        conformances: Set<KnownProtocol>,
        provenances: [ConformanceMap.Provenance] = [],
        strategy: DerivationStrategy = .userGen
    ) -> ConformanceMap.Entry {
        ConformanceMap.Entry(
            typeName: typeName,
            conformances: conformances,
            provenances: provenances.isEmpty
                ? [ConformanceMap.Provenance(filePath: "/p/\(typeName).swift", line: 1, kind: .primary)]
                : provenances,
            derivationStrategy: strategy
        )
    }

    // MARK: - Single-type happy paths

    @Test func emitsEquatableSuite() {
        let map = ConformanceMap(entries: [entry("Foo", conformances: [.equatable])], parseFailures: [])
        let output = GeneratedFileEmitter.emit(target: "MyModule", map: map)
        #expect(output.contains("import Testing"))
        #expect(output.contains("import PropertyLawKit"))
        #expect(output.contains("// Target: MyModule"))
        #expect(output.contains("// Types detected: 1"))
        #expect(output.contains("@Suite struct FooPropertyLawTests {"))
        #expect(output.contains("@Test func equatable_Foo() async throws {"))
        #expect(output.contains("try await checkEquatablePropertyLaws("))
        #expect(output.contains("for: Foo.self,"))
        #expect(output.contains("using: Foo.gen()"))
    }

    @Test func emitsHashableSubsumesEquatable() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [entry("Foo", conformances: [.hashable])], parseFailures: [])
        )
        #expect(output.contains("checkHashablePropertyLaws"))
        // Equatable check NOT emitted — subsumed.
        #expect(output.contains("checkEquatablePropertyLaws") == false)
    }

    @Test func emitsCodableAndEquatable() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Record", conformances: [.equatable, .codable])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func equatable_Record() async throws {"))
        #expect(output.contains("@Test func codable_Record() async throws {"))
        let equatableRange = output.range(of: "equatable_Record")!
        let codableRange = output.range(of: "codable_Record")!
        #expect(equatableRange.lowerBound < codableRange.lowerBound)
    }

    // MARK: - Provenance comments

    @Test func provenanceCommentListsAllSources() {
        let provenances = [
            ConformanceMap.Provenance(
                filePath: "Sources/MyModule/Foo.swift",
                line: 1,
                kind: .primary
            ),
            ConformanceMap.Provenance(
                filePath: "Sources/MyModule/Foo+Hashable.swift",
                line: 3,
                kind: .extension
            )
        ]
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Foo", conformances: [.hashable], provenances: provenances)],
                parseFailures: []
            )
        )
        #expect(output.contains("Sources/MyModule/Foo.swift:1 (primary)"))
        #expect(output.contains("Sources/MyModule/Foo+Hashable.swift:3 (extension)"))
    }

    // MARK: - Idempotence

    @Test func emittingTwiceProducesByteIdenticalOutput() {
        let map = ConformanceMap(
            entries: [
                entry("Bar", conformances: [.hashable]),
                entry("Foo", conformances: [.equatable])
            ],
            parseFailures: []
        )
        let firstRun = GeneratedFileEmitter.emit(target: "X", map: map)
        let secondRun = GeneratedFileEmitter.emit(target: "X", map: map)
        #expect(firstRun == secondRun)
    }

    // MARK: - Suppression markers

    @Test func suppressedTestEmitsCommentStubAndPreservesMarker() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Foo", conformances: [.equatable, .codable])],
                parseFailures: []
            ),
            suppressions: ["codable_Foo"]
        )
        // Equatable test still emitted.
        #expect(output.contains("@Test func equatable_Foo() async throws {"))
        // Codable test replaced by suppression marker + comment stub.
        #expect(output.contains("// property-law-suppress: codable_Foo"))
        #expect(output.contains("(checkCodablePropertyLaws for Foo suppressed"))
        #expect(output.contains("@Test func codable_Foo") == false)
    }

    // MARK: - Edge cases

    @Test func emptyMapEmitsHeaderAndImportsOnly() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [], parseFailures: [])
        )
        #expect(output.contains("// Types detected: 0"))
        #expect(output.contains("import PropertyLawKit"))
        #expect(output.contains("@Suite") == false)
    }

    @Test func parseFailuresAreSurfacedInHeader() {
        let map = ConformanceMap(
            entries: [],
            parseFailures: [
                ConformanceMap.ParseFailure(
                    filePath: "/path/Bad.swift",
                    message: "unreadable"
                )
            ]
        )
        let output = GeneratedFileEmitter.emit(target: "X", map: map)
        #expect(output.contains("Parse failures (1):"))
        #expect(output.contains("/path/Bad.swift: unreadable"))
    }

    @Test func emptyConformancesEmitNoEmitComment() {
        // The scanner filters unemittable protocols (IteratorProtocol,
        // Strideable) upstream; an empty conformance set is the wire form
        // the emitter sees for types whose only recognized stdlib
        // conformance was unemittable.
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Cursor", conformances: [])],
                parseFailures: []
            )
        )
        #expect(output.contains("// No emit-able stdlib conformance"))
        #expect(output.contains("@Suite struct CursorPropertyLawTests") == false)
    }

    // MARK: - M3 derivation strategies

    @Test func caseIterableEntryEmitsAllCasesGenerator() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Status", conformances: [.equatable], strategy: .caseIterable)],
                parseFailures: []
            )
        )
        #expect(output.contains("using: Gen<Status?>.element(of: Status.allCases).compactMap { $0 }"))
        #expect(output.contains("Status.gen()") == false)
    }

    @Test func rawRepresentableEntryEmitsLiftedGenerator() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Direction", conformances: [.equatable], strategy: .rawRepresentable(.string))],
                parseFailures: []
            )
        )
        #expect(output.contains("Gen<Character>.letterOrNumber.string(of: 0...8)"))
        #expect(output.contains("compactMap { Direction(rawValue: $0) }"))
        #expect(output.contains("Direction.gen()") == false)
    }

    @Test func intRawRepresentableEntryEmitsIntGenerator() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Code", conformances: [.equatable], strategy: .rawRepresentable(.int))],
                parseFailures: []
            )
        )
        #expect(output.contains("Gen<Int>.int()"))
        #expect(output.contains("compactMap { Code(rawValue: $0) }"))
    }

    @Test func randomAccessSubsumesBidirectionalAndCollection() {
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Buffer", conformances: [.randomAccessCollection])],
                parseFailures: []
            )
        )
        #expect(output.contains("checkRandomAccessCollectionPropertyLaws"))
        // Subsumed protocols' check calls NOT emitted.
        #expect(output.contains("checkBidirectionalCollectionPropertyLaws") == false)
        #expect(output.contains("checkCollectionPropertyLaws") == false)
    }

    @Test func mutableAndRangeReplaceableEmitAsIndependentSiblings() {
        // MutableCollection and RangeReplaceableCollection both refine
        // Collection but not each other — both survive the most-specific
        // dedupe and emit independently.
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry(
                    "Buffer",
                    conformances: [.mutableCollection, .rangeReplaceableCollection]
                )],
                parseFailures: []
            )
        )
        #expect(output.contains("checkMutableCollectionPropertyLaws"))
        #expect(output.contains("checkRangeReplaceableCollectionPropertyLaws"))
        #expect(output.contains("checkCollectionPropertyLaws") == false)
    }

    @Test func memberwiseStrategyEmitsZipMapComposition() {
        // PRD §5.7 Strategy 3 — the plugin emits the zip+map composition
        // through the type's synthesized memberwise initializer. The
        // exact text is locked in `MemberwiseEmitterTests`; this test
        // just confirms the plugin reaches the same emitter rather than
        // falling back to `<TypeName>.gen()`.
        let strategy: DerivationStrategy = .memberwiseArbitrary(members: [
            MemberSpec(name: "easting", rawType: .int),
            MemberSpec(name: "northing", rawType: .int)
        ])
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry(
                    "Coordinate",
                    conformances: [.equatable],
                    strategy: strategy
                )],
                parseFailures: []
            )
        )
        #expect(output.contains("zip(Gen<Int>.int(), Gen<Int>.int())"))
        #expect(output.contains("Coordinate(easting: $0.0, northing: $0.1)"))
        #expect(output.contains("Coordinate.gen()") == false)
    }

    @Test func todoEntryEmitsUserGenReference() {
        // .todo falls back to <TypeName>.gen() as the placeholder reference;
        // the user gets a compile error pointing at the missing symbol.
        let output = GeneratedFileEmitter.emit(
            target: "X",
            map: ConformanceMap(
                entries: [entry("Coordinate", conformances: [.equatable], strategy: .todo(reason: "test"))],
                parseFailures: []
            )
        )
        #expect(output.contains("using: Coordinate.gen()"))
    }

    // MARK: - v1.8 kit-defined algebraic protocols

    @Test func emitsSemigroupSuite() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(entries: [entry("Counter", conformances: [.semigroup])], parseFailures: [])
        )
        #expect(output.contains("@Test func semigroup_Counter() async throws {"))
        #expect(output.contains("try await checkSemigroupPropertyLaws("))
    }

    @Test func emitsBareMonoidEmitsOnlyMonoidCall() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Tally", conformances: [.monoid])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func monoid_Tally() async throws {"))
        #expect(output.contains("try await checkMonoidPropertyLaws("))
        #expect(output.contains("checkSemigroupPropertyLaws") == false)
    }

    // MARK: - v1.9 kit-defined CommutativeMonoid / Group / Semilattice

    @Test func emitsBareCommutativeMonoidEmitsOnlyCMonCall() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("Tally", conformances: [.commutativeMonoid])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func commutativeMonoid_Tally() async throws {"))
        #expect(output.contains("try await checkCommutativeMonoidPropertyLaws("))
        #expect(output.contains("checkMonoidPropertyLaws") == false)
        #expect(output.contains("checkSemigroupPropertyLaws") == false)
    }

    @Test func emitsBareGroupEmitsOnlyGroupCall() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("AdditiveInt", conformances: [.group])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func group_AdditiveInt() async throws {"))
        #expect(output.contains("try await checkGroupPropertyLaws("))
        #expect(output.contains("checkMonoidPropertyLaws") == false)
        #expect(output.contains("checkSemigroupPropertyLaws") == false)
    }

    @Test func emitsBareSemilatticeEmitsOnlySemilatticeCall() {
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("MaxInt", conformances: [.semilattice])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func semilattice_MaxInt() async throws {"))
        #expect(output.contains("try await checkSemilatticePropertyLaws("))
        #expect(output.contains("checkCommutativeMonoidPropertyLaws") == false)
        #expect(output.contains("checkMonoidPropertyLaws") == false)
        #expect(output.contains("checkSemigroupPropertyLaws") == false)
    }

    @Test func emitsCommutativeMonoidPlusGroupAsTwoCalls() {
        // Incomparable arms in the protocol DAG — both checks emitted.
        let output = GeneratedFileEmitter.emit(
            target: "MyModule",
            map: ConformanceMap(
                entries: [entry("AdditiveInt", conformances: [.commutativeMonoid, .group])],
                parseFailures: []
            )
        )
        #expect(output.contains("@Test func commutativeMonoid_AdditiveInt() async throws {"))
        #expect(output.contains("@Test func group_AdditiveInt() async throws {"))
        #expect(output.contains("try await checkCommutativeMonoidPropertyLaws("))
        #expect(output.contains("try await checkGroupPropertyLaws("))
    }
}

// swiftlint:enable type_body_length
