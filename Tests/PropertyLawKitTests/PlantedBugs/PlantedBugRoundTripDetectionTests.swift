import Testing
import PropertyBased
@testable import PropertyLawKit

// Same PRD §8 self-test gate as `PlantedBugDetectionTests`, split from it
// when that file passed SwiftLint's 400-line ceiling. The seam is by law
// shape rather than arbitrary: the sibling file holds the *relational*
// protocols (Equatable / Hashable / Comparable), whose laws constrain how
// two values compare, while these hold the *round-trip* ones, whose laws
// say a conversion out and back returns what went in.

/// PRD §8 framework self-test gate, round-trip half. Each test plants a
/// violation and asserts the framework catches it. If any of these regress
/// green-on-buggy, the framework has lost the ability to detect that class of
/// violation and shouldn't be released.
struct PlantedBugRoundTripDetectionTests {

    // MARK: - Strideable Strict-tier planted bugs

    @Test func detectsZeroAdvanceJump() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkStrideablePropertyLaws(
                for: ZeroAdvanceJump.self,
                using: Gen<ZeroAdvanceJump>.zeroAdvanceJump(),
                strideGenerator: Gen<Int>.int(in: -10...10),
                options: LawCheckOptions(budget: .standard),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Strideable.zeroAdvanceIdentity"),
            "expected zeroAdvanceIdentity in violation set; got: \(laws)"
        )
    }

    @Test func detectsLyingSelfDistance() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkStrideablePropertyLaws(
                for: LyingSelfDistance.self,
                using: Gen<LyingSelfDistance>.lyingSelfDistance(),
                strideGenerator: Gen<Int>.int(in: -10...10),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Strideable.selfDistanceIsZero"),
            "expected selfDistanceIsZero in violation set; got: \(laws)"
        )
    }

    @Test func detectsOffByOneAdvanceRoundTrips() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkStrideablePropertyLaws(
                for: OffByOneAdvance.self,
                using: Gen<OffByOneAdvance>.offByOneAdvance(),
                strideGenerator: Gen<Int>.int(in: -10...10),
                options: LawCheckOptions(budget: .sanity),
                laws: .ownOnly
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Strideable.distanceRoundTrip")
                || laws.contains("Strideable.advanceRoundTrip"),
            "expected a round-trip law in violation set; got: \(laws)"
        )
    }

    // MARK: - RawRepresentable Strict-tier planted bug

    @Test func detectsLossyRawValueRoundTrip() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkRawRepresentablePropertyLaws(
                for: LossyRawValue.self,
                using: Gen<LossyRawValue>.lossyRawValue(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("RawRepresentable.roundTrip"),
            "expected RawRepresentable.roundTrip in violation set; got: \(laws)"
        )
    }

    // MARK: - LosslessStringConvertible Strict-tier planted bug

    @Test func detectsDoublyDescribedRoundTrip() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkLosslessStringConvertiblePropertyLaws(
                for: DoublyDescribed.self,
                using: Gen<DoublyDescribed>.doublyDescribed(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("LosslessStringConvertible.roundTrip"),
            "expected LosslessStringConvertible.roundTrip in violation set; got: \(laws)"
        )
    }

    // MARK: - Identifiable Conventional-tier planted bug

    @Test func ephemeralIDDoesNotThrowByDefault() async throws {
        // Conventional-tier violation: warns but doesn't throw at default enforcement. The comment
        // said "warns" long before the kit actually did — the warning went nowhere. It is a recorded
        // Testing issue now, which is what `withKnownIssue` is acknowledging.
        await withKnownIssue("the Conventional violation is visible now — it still does not throw") {
            let results = try await checkIdentifiablePropertyLaws(
                for: EphemeralID.self,
                using: Gen<EphemeralID>.ephemeralID(),
                options: LawCheckOptions(budget: .sanity)
            )
            #expect(results.contains { $0.isViolation })
            #expect(results.contains { $0.protocolLaw == "Identifiable.idStability" })
        }
    }

    @Test func ephemeralIDThrowsUnderStrictEnforcement() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkIdentifiablePropertyLaws(
                for: EphemeralID.self,
                using: Gen<EphemeralID>.ephemeralID(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("Identifiable.idStability"),
            "expected Identifiable.idStability in violation set; got: \(laws)"
        )
    }

    // MARK: - CaseIterable Strict-tier planted bug

    @Test func detectsDuplicatingCasesInAllCases() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkCaseIterablePropertyLaws(
                for: DuplicatingCases.self,
                using: Gen<DuplicatingCases>.duplicatingCases(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("CaseIterable.exactlyOnce"),
            "expected CaseIterable.exactlyOnce in violation set; got: \(laws)"
        )
    }

    // MARK: - Codable round-trip planted bug + .partial mode

    @Test func detectsDroppingFieldUnderStrictMode() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkCodablePropertyLaws(
                for: DroppingFieldRecord.self,
                using: Gen<DroppingFieldRecord>.droppingFieldRecord(),
                config: CodableLawConfig(mode: .strict, codec: .json),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Codable.roundTripFidelity[JSON]"))
    }

    @Test func droppingFieldPassesPartialModeForRetainedFieldOnly() async throws {
        let results = try await checkCodablePropertyLaws(
            for: DroppingFieldRecord.self,
            using: Gen<DroppingFieldRecord>.droppingFieldRecord(),
            config: CodableLawConfig(mode: .partial(fields: [\DroppingFieldRecord.id])),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(
            !results[0].isViolation,
            "partial mode listing only \\.id should ignore the dropped secret field"
        )
    }

    @Test func droppingFieldFailsPartialModeWhenSecretIsListed() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkCodablePropertyLaws(
                for: DroppingFieldRecord.self,
                using: Gen<DroppingFieldRecord>.droppingFieldRecord(),
                config: CodableLawConfig(mode: .partial(fields: [\DroppingFieldRecord.secret])),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.contains("Codable.roundTripFidelity[JSON]"))
    }
}
