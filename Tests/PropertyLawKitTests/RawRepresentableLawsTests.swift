import PropertyBased
@testable import PropertyLawKit
import Testing

/// A small custom RawRepresentable struct (not an enum) so the test
/// exercises the user-defined case where `init?(rawValue:)` is hand-written
/// rather than synthesized.
struct PortNumber: RawRepresentable, Equatable, Sendable, CustomStringConvertible {
    let rawValue: UInt16

    init?(rawValue: UInt16) {
        guard rawValue >= 1_024 else { return nil }
        self.rawValue = rawValue
    }

    var description: String { "Port(\(rawValue))" }
}

/// A String-raw enum where RawRepresentable is synthesized — the canonical
/// usage pattern. Don't add an explicit `: RawRepresentable` here; the
/// raw-type clause already implies it, and listing both confuses the
/// CaseIterable synthesis (allCases would then be inferred as `[Self?]`).
enum CompassPoint: String, CaseIterable, Equatable, Sendable {
    case north, south, east, west
}

struct RawRepresentableLawsTests {

    @Test func customStructPassesRoundTrip() async throws {
        let results = try await checkRawRepresentablePropertyLaws(
            for: PortNumber.self,
            using: Gen<PortNumber>.portNumber(),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for PortNumber")
        }
    }

    @Test func synthesizedEnumPassesRoundTrip() async throws {
        let results = try await checkRawRepresentablePropertyLaws(
            for: CompassPoint.self,
            using: Gen<CompassPoint?>.element(of: CompassPoint.allCases).compactMap(\.self),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for CompassPoint")
        }
    }

    @Test func roundTripIsTheOnlyOwnLaw() async throws {
        let results = try await checkRawRepresentablePropertyLaws(
            for: CompassPoint.self,
            using: Gen<CompassPoint?>.element(of: CompassPoint.allCases).compactMap(\.self),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 1)
        #expect(results[0].protocolLaw == "RawRepresentable.roundTrip")
        #expect(results[0].tier == .strict)
    }
}

extension Gen where Value == PortNumber {
    static func portNumber() -> Generator<PortNumber, some SendableSequenceType> {
        Gen<Int>.int(in: 1_024...65_535).compactMap { PortNumber(rawValue: UInt16($0)) }
    }
}
