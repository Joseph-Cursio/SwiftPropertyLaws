import PropertyBased
@testable import PropertyLawKit
import Testing

/// Stable Identifiable: id is a stored property — re-reads return the same value.
struct StableUser: Identifiable, Sendable, CustomStringConvertible {
    let id: Int
    let name: String
    var description: String { "User#\(id)(\(name))" }
}

struct IdentifiableLawsTests {

    @Test func storedIdPassesIdStability() async throws {
        let results = try await checkIdentifiablePropertyLaws(
            for: StableUser.self,
            using: Gen<StableUser>.stableUser(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for StableUser")
        }
    }

    @Test func idStabilityIsTheOnlyOwnLaw() async throws {
        let results = try await checkIdentifiablePropertyLaws(
            for: StableUser.self,
            using: Gen<StableUser>.stableUser(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results[0].protocolLaw == "Identifiable.idStability")
        #expect(results[0].tier == .conventional)
    }
}

extension Gen where Value == StableUser {
    static func stableUser() -> Generator<StableUser, some SendableSequenceType> {
        zip(Gen<Int>.int(in: 0...10_000), Gen<Character>.letterOrNumber.string(of: 1...4))
            .map { StableUser(id: $0, name: $1) }
    }
}
