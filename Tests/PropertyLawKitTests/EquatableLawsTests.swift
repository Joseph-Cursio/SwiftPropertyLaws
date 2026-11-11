import PropertyBased
@testable import PropertyLawKit
import Testing

struct EquatableLawsTests {

    @Test func intsPassAllStrictLaws() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 4)
        for result in results {
            #expect(
                result.isViolation == false,
                "\(result.protocolLaw) should pass for Int"
            )
            #expect(result.tier == .strict)
        }
    }

    @Test func stringsPassAllStrictLaws() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: String.self,
            using: TestGen.smallString(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 4)
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for String")
        }
    }

    @Test func customStructPassesAllStrictLaws() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Coordinate.self,
            using: Gen<Coordinate>.coordinate(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 4)
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Coordinate")
        }
    }

    @Test func resultsCarryReplayableSeed() async throws {
        let pinnedSeed = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity, seed: pinnedSeed)
        )
        #expect(results.isEmpty == false)
        for result in results {
            #expect(result.seed == pinnedSeed)
            #expect(result.environment.backendIdentity == "swift-property-based")
        }
    }

    @Test func eachLawCarriesItsOwnAttributableName() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let laws = Set(results.map(\.protocolLaw))
        #expect(laws == [
            "Equatable.reflexivity",
            "Equatable.symmetry",
            "Equatable.transitivity",
            "Equatable.negationConsistency",
        ])
    }
}
