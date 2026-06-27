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
}
