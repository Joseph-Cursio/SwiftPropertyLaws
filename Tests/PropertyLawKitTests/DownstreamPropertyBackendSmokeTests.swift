import PropertyLawKit
import Testing

/// Smoke test for the `PropertyBackend` + `SwiftPropertyBasedBackend` +
/// `Seed` + `BackendCheckResult` surface a downstream consumer
/// (SwiftInferProperties M5's lifted-test stub writeout) will exercise.
/// **Intentionally uses plain `import PropertyLawKit`** (not `@testable`)
/// so the file compiles only against the public surface — anything
/// missing surfaces here as a compile error rather than waiting until
/// SwiftInferProperties M5 actually tries to consume it.
///
/// Mirrors SwiftInferProperties' M3.1 `DerivationStrategistSmokeTests`
/// pattern — single, narrow proof that the dep wiring lands a usable
/// API surface in the consumer's namespace.
@Suite("PropertyBackend — downstream-consumer smoke (K-prep-M2)")
struct DownstreamPropertyBackendSmokeTests {

    // MARK: - Seed construction is reachable from public surface

    @Test
    func seedConstructibleFromExplicitState() {
        let seed = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        #expect(seed.stateA == 1)
        #expect(seed.stateB == 2)
        #expect(seed.stateC == 3)
        #expect(seed.stateD == 4)
    }

    // MARK: - SwiftPropertyBasedBackend round-trip

    @Test
    func defaultBackendInitializerIsReachable() {
        let backend = SwiftPropertyBasedBackend()
        #expect(backend.identifier == "swift-property-based")
    }

    @Test
    func customIdentifierFlowsThroughInit() {
        let backend = SwiftPropertyBasedBackend(identifier: "swift-infer-lifted-test")
        #expect(backend.identifier == "swift-infer-lifted-test")
    }

    @Test
    func backendChecksAlwaysTruePropertyAndReportsPassed() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(stateA: 0xABCDEF1234567890, stateB: 0, stateC: 0, stateD: 0)
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng -> Int in Int.random(in: 0...1_000, using: &rng) },
            property: { _ in true }
        )
        switch result {
        case .passed(let trialsRun, _):
            #expect(trialsRun == 100)

        case .failed:
            Issue.record("Always-true property should not fail")
        }
    }

    @Test
    func backendChecksAlwaysFalsePropertyAndReportsFailedOnFirstTrial() async {
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng -> Int in Int.random(in: 0...1_000, using: &rng) },
            property: { _ in false }
        )
        switch result {
        case .passed:
            Issue.record("Always-false property should fail")

        case let .failed(trialsRun, _, _, error):
            // Short-circuit on first false return per `PropertyBackend` doc.
            #expect(trialsRun == 1)
            #expect(error == nil)
        }
    }

    @Test
    func backendCapturesThrownErrorInErrorBox() async {
        struct LiftedTestStubError: Error {
            let message = "stub failure"
        }
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let result = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng -> Int in Int.random(in: 0...1_000, using: &rng) },
            property: { _ -> Bool in throw LiftedTestStubError() }
        )
        switch result {
        case .passed:
            Issue.record("Throwing property should fail")

        case .failed(_, _, _, let error):
            // ErrorBox preserves the thrown error's description without
            // forcing the error type to be Sendable (PRD §4.5).
            let box = try? #require(error)
            #expect(box?.message.contains("LiftedTestStubError") == true)
        }
    }

    // MARK: - Replay reproducibility

    @Test
    func twoChecksWithSameSeedSampleSameInputs() async {
        // Reproducibility is the load-bearing property for the M5+
        // lifted-test stub: a developer captures a counterexample under
        // a recorded seed, re-runs the test under that same seed, gets
        // the same counterexample. This test verifies the seed-replay
        // contract from the consumer surface (not the kit's internal
        // tests) — same seed → same first-failing input.
        let backend = SwiftPropertyBasedBackend()
        let seed = Seed(stateA: 0x0123456789ABCDEF, stateB: 1, stateC: 2, stateD: 3)
        var firstFailingInput: Int?
        var secondFailingInput: Int?
        let firstResult = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng -> Int in Int.random(in: 0...1_000, using: &rng) },
            property: { value -> Bool in value < 500 }
        )
        if case let .failed(_, _, value, _) = firstResult { firstFailingInput = value }
        let secondResult = await backend.check(
            trials: 100,
            seed: seed,
            sample: { rng -> Int in Int.random(in: 0...1_000, using: &rng) },
            property: { value -> Bool in value < 500 }
        )
        if case let .failed(_, _, value, _) = secondResult { secondFailingInput = value }
        #expect(firstFailingInput != nil)
        #expect(firstFailingInput == secondFailingInput)
    }
}
