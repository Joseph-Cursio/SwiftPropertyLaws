import Testing
@testable import PropertyLawCore

/// Tier 2 of the generator-derivation strengthening (Idea #3): members
/// typed as known value types outside the `RawType` set — `Character`
/// (stdlib) and `Date` (Foundation) — now derive curated engine
/// generators, and `Date`'s `Foundation` requirement is carried up as an
/// import so the discovery plugin can emit it.
struct KnownValueTypeDerivationTests {

    // MARK: - Character (stdlib, no import)

    @Test func characterUsesLetterOrNumberGenerator() {
        let composed = DerivationStrategist.composedGenerator(forTypeName: "Character")
        #expect(composed?.expression == "Gen<Character>.letterOrNumber")
        #expect(composed?.requiredImports == [])
    }

    @Test func characterComposesInsideCollections() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[Character]")
                == "Gen<Character>.letterOrNumber.array(of: 0...8)"
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Character?")
                == "Gen<Character>.letterOrNumber.optional"
        )
    }

    // MARK: - Date (Foundation)

    @Test func dateUsesBuiltInGeneratorAndRequiresFoundation() {
        let composed = DerivationStrategist.composedGenerator(forTypeName: "Date")
        #expect(composed?.expression == "Gen<Date>.date")
        #expect(composed?.requiredImports == ["Foundation"])
    }

    @Test func dateImportPropagatesThroughComposites() {
        for spelling in ["[Date]", "Date?", "Set<Date>", "[String: Date]"] {
            #expect(
                DerivationStrategist.composedGenerator(forTypeName: spelling)?
                    .requiredImports == ["Foundation"],
                "expected Foundation import for \(spelling)"
            )
        }
    }

    // MARK: - Common Foundation value types → curated kit generators

    @Test func uuidUsesCuratedKitGeneratorAndRequiresFoundation() {
        let composed = DerivationStrategist.composedGenerator(forTypeName: "UUID")
        #expect(composed?.expression == "Gen<UUID>.uuid()")
        #expect(composed?.requiredImports == ["Foundation"])
    }

    @Test func dataUsesCuratedKitGeneratorAndRequiresFoundation() {
        let composed = DerivationStrategist.composedGenerator(forTypeName: "Data")
        #expect(composed?.expression == "Gen<Data>.data()")
        #expect(composed?.requiredImports == ["Foundation"])
    }

    @Test func urlUsesCuratedKitGeneratorAndRequiresFoundation() {
        let composed = DerivationStrategist.composedGenerator(forTypeName: "URL")
        #expect(composed?.expression == "Gen<URL>.url()")
        #expect(composed?.requiredImports == ["Foundation"])
    }

    @Test func decimalUsesCuratedKitGeneratorAndRequiresFoundation() {
        let composed = DerivationStrategist.composedGenerator(forTypeName: "Decimal")
        #expect(composed?.expression == "Gen<Decimal>.decimal()")
        #expect(composed?.requiredImports == ["Foundation"])
    }

    @Test func foundationValueTypesPropagateImportThroughComposites() {
        for spelling in ["[UUID]", "Data?", "Set<URL>", "[String: Decimal]"] {
            #expect(
                DerivationStrategist.composedGenerator(forTypeName: spelling)?
                    .requiredImports == ["Foundation"],
                "expected Foundation import for \(spelling)"
            )
        }
    }

    @Test func structWithUUIDMemberDerivesAndRequiresFoundation() {
        let shape = TypeShape(
            name: "Token",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "identifier", typeName: "UUID"),
                StoredMember(name: "payload", typeName: "Data")
            ]
        )
        let strategy = DerivationStrategist.strategy(for: shape)
        guard case .memberwiseArbitrary = strategy else {
            Issue.record("expected memberwise derivation for struct with UUID + Data members")
            return
        }
        #expect(strategy.requiredImports == ["Foundation"])
    }

    // MARK: - Known stdlib/Foundation typealiases

    @Test func timeIntervalResolvesToDouble() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "TimeInterval")
                == "Gen<Double>.double(in: -1_000_000...1_000_000)"
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[TimeInterval]")
                == "Gen<Double>.double(in: -1_000_000...1_000_000).array(of: 0...8)"
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Float32")
                == "Gen<Float>.float(in: -1_000_000...1_000_000)"
        )
    }

    // MARK: - Strategy-level import aggregation

    @Test func structWithDateMemberDerivesAndRequiresFoundation() {
        let shape = TypeShape(
            name: "Event",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "id", typeName: "Int"),
                StoredMember(name: "occurredAt", typeName: "Date")
            ]
        )
        let strategy = DerivationStrategist.strategy(for: shape)
        guard case .memberwiseArbitrary = strategy else {
            Issue.record("expected memberwise derivation for struct with Date member")
            return
        }
        #expect(strategy.requiredImports == ["Foundation"])
    }

    @Test func stdlibOnlyStructRequiresNoImports() {
        let shape = TypeShape(
            name: "Point",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "x", typeName: "Int"),
                StoredMember(name: "tags", typeName: "[String]")
            ]
        )
        #expect(DerivationStrategist.strategy(for: shape).requiredImports == [])
    }

    /// `Unicode.Scalar` was an enum-payload blocker on the swift.org corpus and
    /// the only *stdlib* one in the tail. A mutant removing its arm from
    /// `knownValueGenerator` survived until this test existed — nothing
    /// asserted that a scalar-typed member actually derives.
    @Test("a Unicode.Scalar member derives")
    func unicodeScalarMemberDerives() {
        let shape = TypeShape(
            name: "Glyph",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "scalar", typeName: "Unicode.Scalar"),
                StoredMember(name: "legacy", typeName: "UnicodeScalar")
            ]
        )
        guard case .memberwiseArbitrary(let members) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected memberwise derivation")
            return
        }
        #expect(members.allSatisfy {
            $0.generatorExpression == "Gen<Unicode.Scalar>.unicodeScalar()"
        })
        // Stdlib, not Foundation — no extra import beyond the emitters' default.
        #expect(members.allSatisfy { $0.requiredImports.isEmpty })
    }

    /// The enum path is the one the corpus measured, so pin it too.
    @Test("a Unicode.Scalar enum payload derives")
    func unicodeScalarPayloadDerives() {
        let shape = TypeShape(
            name: "Token",
            kind: .enum,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            enumCases: [EnumCase(name: "scalar", associatedValues: [
                InitializerParameter(label: nil, typeName: "Unicode.Scalar")
            ])]
        )
        guard case .enumCases = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected case enumeration")
            return
        }
    }
}
