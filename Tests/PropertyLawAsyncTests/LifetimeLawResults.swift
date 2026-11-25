import PropertyBased
import PropertyLawAsync
import PropertyLawKit
import Testing

/// Runs the lifetime laws on a planted operator and reports which failed.
enum LifetimeLawResults {
    static let samples = Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 6)
    static let singleElementSamples = Gen<Int>.int(in: -100 ... 100).array(of: 1 ... 1)

    /// The counterexample of each lifetime law that failed on `operation`,
    /// keyed by law, over samples drawn from `generator`.
    static func failures<Output: AsyncSequence & Sendable, Shrinker: SendableSequenceType>(
        using generator: Generator<[Int], Shrinker>,
        _ operation: @escaping @Sendable (LifetimeProbeSource<Int>, LawClock) -> Output
    ) async throws -> [AsyncLifetimeLaw: String] {
        do {
            let results = try await checkAsyncLifetimePropertyLaws(
                for: [Int].self,
                using: generator,
                options: LawCheckOptions(budget: .sanity),
                applying: operation
            )
            #expect(results.count == AsyncLifetimeLaw.allCases.count)
            return [:]
        } catch let violation as PropertyLawViolation {
            var failed: [AsyncLifetimeLaw: String] = [:]
            for result in violation.results {
                let name = String(result.protocolLaw.dropFirst("AsyncLifetime.".count))
                let law = try #require(AsyncLifetimeLaw(rawValue: name), "unexpected law \(result.protocolLaw)")
                failed[law] = result.counterexample ?? ""
            }
            return failed
        }
    }

    /// ``failures(using:_:)`` over ``samples``.
    static func failures<Output: AsyncSequence & Sendable>(
        _ operation: @escaping @Sendable (LifetimeProbeSource<Int>, LawClock) -> Output
    ) async throws -> [AsyncLifetimeLaw: String] {
        try await failures(using: samples, operation)
    }
}
