import PropertyBased
@testable import PropertyLawKit
import Testing

/// A normal CaseIterable enum — synthesized allCases is well-formed.
enum TrafficLight: CaseIterable, Hashable, Sendable {
    case red, yellow, green
}

struct CaseIterableLawsTests {

    @Test func synthesizedEnumPassesExactlyOnce() async throws {
        let results = try await checkCaseIterablePropertyLaws(
            for: TrafficLight.self,
            using: Gen<TrafficLight>.trafficLight(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for TrafficLight")
        }
    }

    @Test func exactlyOnceIsTheOnlyOwnLaw() async throws {
        let results = try await checkCaseIterablePropertyLaws(
            for: TrafficLight.self,
            using: Gen<TrafficLight>.trafficLight(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results[0].protocolLaw == "CaseIterable.exactlyOnce")
        #expect(results[0].tier == .strict)
    }
}

extension Gen where Value == TrafficLight {
    static func trafficLight() -> Generator<TrafficLight, some SendableSequenceType> {
        Gen<TrafficLight?>.element(of: TrafficLight.allCases).compactMap(\.self)
    }
}
