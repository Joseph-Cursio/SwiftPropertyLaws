import Foundation
import PropertyBased
@testable import PropertyLawAsync
import PropertyLawKit
import Testing

/// Records every sample a generator hands out.
private final class DrawLog: @unchecked Sendable {
    private let lock = NSLock()
    private var draws: [String] = []

    func record(_ value: [Int]) {
        lock.lock()
        draws.append("\(value)")
        lock.unlock()
    }

    func take() -> [String] {
        lock.lock()
        defer {
            draws = []
            lock.unlock()
        }
        return draws
    }
}

/// FNV-1a over the samples, so a pin holds a few hundred draws in one value.
private func digest(_ strings: [String]) -> String {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in strings.joined(separator: "|").utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return String(hash, radix: 16)
}

/// FIFO is byte-identical to the scheduler before the seeded order existed.
///
/// Every literal here was captured on `main` at d31d54c, before M3 changed
/// anything: the timed laws' draws, and each planted lifetime defect's
/// failing trial, counterexample, shrink origin and shrink steps, all under
/// one fixed seed. A FIFO run that drew one extra word, printed the
/// schedule-carrying input instead of the sample, or shrank in another order
/// would change one of them.
struct SchedulingPinTests {
    private static let seed = Seed(
        stateA: 0x1234_5678_9ABC_DEF0, stateB: 0x0FED_CBA9_8765_4321, stateC: 42, stateD: 7
    )

    private static func generator(logging log: DrawLog) -> Generator<[Int], some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6).map { value -> [Int] in
            log.record(value)
            return value
        }
    }

    @Test func fifoTimedLawsDrawWhatMainDrew() async throws {
        let log = DrawLog()
        let results = try await checkTimedAsyncSequencePropertyLaws(
            for: [Int].self,
            using: Self.generator(logging: log),
            options: LawCheckOptions(budget: .sanity, seed: Self.seed)
        )
        let draws = log.take()
        #expect(draws.count == 400)
        #expect(digest(draws) == "13088cc685d4a113")
        #expect(Array(draws.prefix(3)) == ["[25, 17, 52]", "[-7, 72]", "[30, -73]"])
        #expect(results.allSatisfy { $0.trials == 100 && $0.outcome == .passed })
        #expect(results.allSatisfy { $0.environment.scheduling == nil })
    }

    /// Under a seeded strategy each trial draws one more word, so the inputs
    /// after the first differ from FIFO's and the fingerprint says so.
    @Test func seededTimedLawsDrawTheScheduleToo() async throws {
        let log = DrawLog()
        let results = try await checkTimedAsyncSequencePropertyLaws(
            for: [Int].self,
            using: Self.generator(logging: log),
            options: LawCheckOptions(budget: .sanity, seed: Self.seed, scheduling: .seeded)
        )
        let draws = log.take()
        #expect(draws.count == 400)
        #expect(draws.first == "[25, 17, 52]")
        #expect(digest(draws) != "13088cc685d4a113")
        #expect(results.allSatisfy { $0.outcome == .passed })
        #expect(results.allSatisfy { $0.environment.scheduling == "seeded/1" })
    }

    private struct Pin {
        let law: AsyncLifetimeLaw
        let trials: Int
        let shrinkSteps: Int
        let counterexample: String
        let shrunkFrom: String
    }

    private static let released = "the consumer called next() once and dropped its iterator, but 1 of the 1 "
        + "upstream iterators the operator made were never released"
    private static let undelivered = "the operator read the upstream failure and then finished without delivering it"
    private static let ignoresCancellation = "hang: the consumer was cancelled and its next() never returned, "
        + "so the operator ignores cancellation (virtual time would pass its horizon of"

    @Test(arguments: [
        ("keepsUpstreamAfterDrop", Pin(
            law: .releasesUpstreamWhenConsumerLeaves, trials: 1, shrinkSteps: 2,
            counterexample: "source = [52]; " + released, shrunkFrom: "source = [25, 17, 52]; " + released
        )),
        ("dropsFailureWithoutDemand", Pin(
            law: .failureReachesConsumerWithoutDemand, trials: 1, shrinkSteps: 2,
            counterexample: "source = [52]; " + undelivered, shrunkFrom: "source = [25, 17, 52]; " + undelivered
        )),
        ("ignoresCancellationInNext", Pin(
            law: .cancellationReachesUpstream, trials: 8, shrinkSteps: 1,
            counterexample: "source = []; " + ignoresCancellation
                + " 0.6 seconds: the next sleeper wakes at 3600.0 seconds)",
            shrunkFrom: "source = [-33]; " + ignoresCancellation
                + " 0.601 seconds: the next sleeper wakes at 3600.001 seconds)"
        )),
    ])
    private func fifoLifetimeFailuresMatchMain(_ name: String, _ pin: Pin) async throws {
        let defect: ForwardingSequence<LifetimeProbeSource<Int>>.Defect = switch name {
        case "keepsUpstreamAfterDrop": .keepsUpstreamAfterDrop
        case "dropsFailureWithoutDemand": .dropsFailureWithoutDemand
        default: .ignoresCancellationInNext
        }
        let log = DrawLog()
        var results: [CheckResult] = []
        do {
            results = try await checkAsyncLifetimePropertyLaws(
                for: [Int].self,
                using: Self.generator(logging: log),
                options: LawCheckOptions(budget: .sanity, seed: Self.seed)
            ) { source, _ in ForwardingSequence(base: source, defect: defect, delay: nil) }
        } catch let violation as PropertyLawViolation {
            results = violation.results
        }
        let lawName = LawIdentifier.asyncLifetime(pin.law).qualifiedName
        let result = try #require(results.first { $0.protocolLaw == lawName })
        #expect(result.trials == pin.trials)
        #expect(result.seed == Self.seed)
        #expect(result.shrinkSteps == pin.shrinkSteps)
        #expect(result.counterexample == pin.counterexample)
        #expect(result.shrunkFrom == pin.shrunkFrom)
        #expect(result.environment.scheduling == nil)
    }
}
