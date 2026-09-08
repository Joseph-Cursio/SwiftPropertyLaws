import Testing
@testable import PropertyLawKit

/// Coverage + regression suite for `LawIdentifier` and the per-protocol
/// law enums (`EquatableLaw`, `HashableLaw`, ..., `SetAlgebraLaw`).
///
/// These enums double as the type-safe entry points to suppression
/// (`LawIdentifier.setAlgebra(.unionIdempotence)`). They have to stay in
/// sync with the runtime law constants emitted by `checkXxxPropertyLaws`
/// — if a law gets added to one side but not the other, suppression
/// silently fails for that law and tests would still pass without these
/// regression guards.
///
/// The `*EnumCoversRuntimeLaws` tests assert the enum's `allCases` covers
/// every law name the corresponding `checkXxxPropertyLaws` actually
/// produces. The original miss that motivated this suite: PRD v0.3 added
/// four `symmetricDifference*` laws to `SetAlgebraLaws.swift` but did not
/// extend `SetAlgebraLaw`, so callers had to fall back to the un-typesafe
/// `LawIdentifier(protocolName:lawName:)` initializer.
struct LawIdentifierTests {

    // MARK: - Factory methods produce well-formed qualified names

    @Test func equatableFactoryProducesCorrectQualifiedNames() {
        for law in EquatableLaw.allCases {
            let id = LawIdentifier.equatable(law)
            #expect(id.protocolName == "Equatable")
            #expect(id.lawName == law.rawValue)
            #expect(id.qualifiedName == "Equatable.\(law.rawValue)")
        }
    }

    @Test func hashableFactoryProducesCorrectQualifiedNames() {
        for law in HashableLaw.allCases {
            let id = LawIdentifier.hashable(law)
            #expect(id.qualifiedName == "Hashable.\(law.rawValue)")
        }
    }

    @Test func comparableFactoryProducesCorrectQualifiedNames() {
        for law in ComparableLaw.allCases {
            let id = LawIdentifier.comparable(law)
            #expect(id.qualifiedName == "Comparable.\(law.rawValue)")
        }
    }

    @Test func codableFactoryProducesCorrectQualifiedNames() {
        for law in CodableLaw.allCases {
            let id = LawIdentifier.codable(law)
            #expect(id.qualifiedName == "Codable.\(law.rawValue)")
        }
    }

    @Test func iteratorProtocolFactoryProducesCorrectQualifiedNames() {
        for law in IteratorProtocolLaw.allCases {
            let id = LawIdentifier.iteratorProtocol(law)
            #expect(id.qualifiedName == "IteratorProtocol.\(law.rawValue)")
        }
    }

    @Test func sequenceFactoryProducesCorrectQualifiedNames() {
        for law in SequenceLaw.allCases {
            let id = LawIdentifier.sequence(law)
            #expect(id.qualifiedName == "Sequence.\(law.rawValue)")
        }
    }

    @Test func collectionFactoryProducesCorrectQualifiedNames() {
        for law in CollectionLaw.allCases {
            let id = LawIdentifier.collection(law)
            #expect(id.qualifiedName == "Collection.\(law.rawValue)")
        }
    }

    @Test func setAlgebraFactoryProducesCorrectQualifiedNames() {
        for law in SetAlgebraLaw.allCases {
            let id = LawIdentifier.setAlgebra(law)
            #expect(id.qualifiedName == "SetAlgebra.\(law.rawValue)")
        }
    }

    @Test func bidirectionalCollectionFactoryProducesCorrectQualifiedNames() {
        for law in BidirectionalCollectionLaw.allCases {
            let id = LawIdentifier.bidirectionalCollection(law)
            #expect(id.qualifiedName == "BidirectionalCollection.\(law.rawValue)")
        }
    }

    @Test func randomAccessCollectionFactoryProducesCorrectQualifiedNames() {
        for law in RandomAccessCollectionLaw.allCases {
            let id = LawIdentifier.randomAccessCollection(law)
            #expect(id.qualifiedName == "RandomAccessCollection.\(law.rawValue)")
        }
    }

    @Test func mutableCollectionFactoryProducesCorrectQualifiedNames() {
        for law in MutableCollectionLaw.allCases {
            let id = LawIdentifier.mutableCollection(law)
            #expect(id.qualifiedName == "MutableCollection.\(law.rawValue)")
        }
    }

    @Test func rangeReplaceableCollectionFactoryProducesCorrectQualifiedNames() {
        for law in RangeReplaceableCollectionLaw.allCases {
            let id = LawIdentifier.rangeReplaceableCollection(law)
            #expect(id.qualifiedName == "RangeReplaceableCollection.\(law.rawValue)")
        }
    }

    // MARK: - Enums cover every runtime law name (anti-divergence guards)

    /// The motivating case for this suite: PRD v0.3 added four
    /// `symmetricDifference*` laws to `SetAlgebraLaws.swift` but `SetAlgebraLaw`
    /// initially missed them. This test asserts the enum's `allCases`
    /// covers every Strict-tier SetAlgebra law name the runtime emits.
    @Test func setAlgebraEnumCoversRuntimeLaws() async throws {
        let results = try await checkSetAlgebraPropertyLaws(
            for: Set<Int>.self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...3).map(Set.init),
            options: LawCheckOptions(budget: .sanity)
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(SetAlgebraLaw.allCases.map { "SetAlgebra.\($0.rawValue)" })
        let missing = runtimeLaws.subtracting(enumLaws)
        #expect(
            missing.isEmpty,
            "SetAlgebraLaw enum is missing cases for: \(missing.sorted().joined(separator: ", "))"
        )
    }

    @Test func equatableEnumCoversRuntimeLaws() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: 0...20),
            options: LawCheckOptions(budget: .sanity)
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(EquatableLaw.allCases.map { "Equatable.\($0.rawValue)" })
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func hashableEnumCoversRuntimeLaws() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: 0...20),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(HashableLaw.allCases.map { "Hashable.\($0.rawValue)" })
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func comparableEnumCoversRuntimeLaws() async throws {
        let results = try await checkComparablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: 0...20),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(ComparableLaw.allCases.map { "Comparable.\($0.rawValue)" })
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func bidirectionalCollectionEnumCoversRuntimeLaws() async throws {
        let results = try await checkBidirectionalCollectionPropertyLaws(
            for: [Int].self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...5),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(
            BidirectionalCollectionLaw.allCases.map { "BidirectionalCollection.\($0.rawValue)" }
        )
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func randomAccessCollectionEnumCoversRuntimeLaws() async throws {
        let results = try await checkRandomAccessCollectionPropertyLaws(
            for: [Int].self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...5),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(
            RandomAccessCollectionLaw.allCases.map { "RandomAccessCollection.\($0.rawValue)" }
        )
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func mutableCollectionEnumCoversRuntimeLaws() async throws {
        let results = try await checkMutableCollectionPropertyLaws(
            for: [Int].self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...5),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(
            MutableCollectionLaw.allCases.map { "MutableCollection.\($0.rawValue)" }
        )
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    @Test func rangeReplaceableCollectionEnumCoversRuntimeLaws() async throws {
        let results = try await checkRangeReplaceableCollectionPropertyLaws(
            for: [Int].self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...5),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly
        )
        let runtimeLaws = Set(results.map(\.protocolLaw))
        let enumLaws = Set(
            RangeReplaceableCollectionLaw.allCases.map {
                "RangeReplaceableCollection.\($0.rawValue)"
            }
        )
        #expect(runtimeLaws.subtracting(enumLaws).isEmpty)
    }

    // MARK: - LawIdentifier Hashable conformance is well-behaved

    @Test func lawIdentifierIsUsableAsSetElement() {
        let ids: Set<LawIdentifier> = [
            .equatable(.reflexivity),
            .equatable(.reflexivity), // duplicate — Set should dedupe
            .hashable(.equalityConsistency),
            .setAlgebra(.symmetricDifferenceDefinition)
        ]
        #expect(ids.count == 3)
        #expect(ids.contains(.equatable(.reflexivity)))
        #expect(ids.contains(.equatable(.symmetry)) == false)
    }

    @Test func lawIdentifierEqualityIsByValue() {
        let lhs = LawIdentifier(protocolName: "Equatable", lawName: "reflexivity")
        let rhs = LawIdentifier.equatable(.reflexivity)
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }

    // MARK: - The exported vocabulary

    /// `allLawNames` must contain every law the runtime actually emits, or a
    /// consumer validating its coverage claims against it gets false negatives
    /// — the failure mode the export exists to remove, reintroduced one layer
    /// up.
    ///
    /// Runs real suites rather than trusting `allCases`: the enums are the source
    /// of the set, so comparing the set to the enums would be circular.
    ///
    /// **The suites are chosen to span the enum split, not for convenience.**
    /// The first version of this test ran SetAlgebra, Equatable, Hashable and
    /// Comparable — all four covered by the original twelve enums, which were
    /// the only ones that existed. It passed while `isKnownLawName` returned
    /// `false` for every law of the other 27 protocols, because it confirmed the
    /// vocabulary against exactly the part of the kit the vocabulary was built
    /// from. AdditiveArithmetic and Numeric are here because they are outside
    /// that twelve; keep at least one such suite in this list.
    @Test func exportedVocabularyCoversEveryEmittedLaw() async throws {
        var emitted: Set<String> = []

        emitted.formUnion(try await checkSetAlgebraPropertyLaws(
            for: Set<Int>.self,
            using: Gen<Int>.int(in: 0...20).array(of: 0...3).map(Set.init),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkEquatablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkHashablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkComparablePropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        // Outside the original twelve enums — the case the first version missed.
        emitted.formUnion(try await checkAdditiveArithmeticPropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        emitted.formUnion(try await checkNumericPropertyLaws(
            for: Int.self,
            using: Gen<Int>.int(in: -20...20),
            options: LawCheckOptions(budget: .sanity)
        ).map(\.protocolLaw))

        #expect(!emitted.isEmpty, "no laws ran; the check below would pass vacuously")

        let unknown = emitted.filter { !LawIdentifier.isKnownLawName($0) }
        #expect(
            unknown.isEmpty,
            """
            These law names are emitted at runtime but absent from \
            LawIdentifier.allLawNames, so a consumer checking against it would \
            call them unknown: \(unknown.sorted().joined(separator: ", "))
            """
        )
    }

    /// The bracketed-backend case, which is the reason `allLawNames` holds base
    /// names and `isKnownLawName` exists at all. `CodableLaw` has one case and
    /// the runner emits `Codable.roundTripFidelity[<codec>]`, so a plain set
    /// membership test on the emitted name fails.
    @Test func backendSuffixIsStrippedBeforeMembership() {
        #expect(LawIdentifier.allLawNames.contains("Codable.roundTripFidelity"))
        #expect(!LawIdentifier.allLawNames.contains("Codable.roundTripFidelity[JSON]"))
        #expect(LawIdentifier.isKnownLawName("Codable.roundTripFidelity[JSON]"))
        #expect(LawIdentifier.baseName(of: "Codable.roundTripFidelity[JSON]")
                == "Codable.roundTripFidelity")
        #expect(LawIdentifier.baseName(of: "Equatable.reflexivity") == "Equatable.reflexivity")
    }

    /// The control. Without it, `isKnownLawName` returning true for everything
    /// would satisfy the two tests above.
    @Test func inventedLawNamesAreNotKnown() {
        #expect(!LawIdentifier.isKnownLawName("SetAlgebra.unionAssociativity"))
        #expect(!LawIdentifier.isKnownLawName("Equatable.notALaw"))
        #expect(!LawIdentifier.isKnownLawName(""))
    }

    /// The aggregate is assembled by hand, one `result +=` per law enum, so a
    /// dropped line silently shrinks the vocabulary.
    ///
    /// Counts distinct protocol names rather than summing every enum's
    /// `allCases`. Summing would mean listing all 39 enums here, which is the
    /// same hand-maintained list one file over and drifts the same way; one
    /// number fails just as loudly when a line goes missing, and adding a
    /// protocol is meant to be a deliberate edit in both places.
    @Test func vocabularyCoversEverySuiteThatShipsLaws() {
        let protocols = Set(LawIdentifier.allLawIdentifiers.map(\.protocolName))
        #expect(
            protocols.count == 39,
            """
            The vocabulary covers \(protocols.count) protocols, not 39. If a law \
            suite was added, add its enum to `allLawIdentifiers` and raise this \
            number; if one was removed, lower it. A silent drop here is the bug \
            that shipped in 4.3.0, where the aggregate covered twelve protocols \
            and claimed to cover all of them.
            """
        )
        #expect(
            LawIdentifier.allLawNames.count == LawIdentifier.allLawIdentifiers.count,
            "two law identifiers share a qualified name"
        )
    }
}
