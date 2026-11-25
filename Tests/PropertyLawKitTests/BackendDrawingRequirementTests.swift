import Foundation
import PropertyBased
import PropertyLawKit
import Testing

// MARK: - Backends written against the public surface

/// SplitMix64: a seeded generator that is not `Xoshiro`, standing in for an
/// engine's own generator.
struct SplitMix64: SeededRandomNumberGenerator {
    private(set) var state: UInt64

    var currentSeed: UInt64 { state }

    init(seed: UInt64) { state = seed }

    init() {
        var system = SystemRandomNumberGenerator()
        state = system.next()
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// Counts how many times a backend's trial loop was entered.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var calls: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}

/// The shape of a backend written before 4.13.0: it implements only the
/// `Xoshiro` requirement, with the loop `SwiftPropertyBasedBackend` had then.
struct XoshiroOnlyBackend: PropertyBackend {
    let identifier = "xoshiro-only"
    let counter = CallCounter()

    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        sample: @Sendable (inout Xoshiro) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        counter.increment()
        let initialSeed = seed ?? Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        var rng = Xoshiro(seed: (initialSeed.stateA, initialSeed.stateB, initialSeed.stateC, initialSeed.stateD))
        for trial in 0 ..< trials {
            let input = sample(&rng)
            guard (try? await property(input)) == true else {
                return .failed(trialsRun: trial + 1, initialSeed: initialSeed, failingInput: input, thrownError: nil)
            }
        }
        return .passed(trialsRun: trials, initialSeed: initialSeed)
    }
}

/// A new engine: it implements only `drawing:` and draws from its own
/// generator, seeded from `Seed.stateA`.
struct SplitMixBackend: DrawingPropertyBackend {
    let identifier = "splitmix"
    let counter = CallCounter()

    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        drawing: @Sendable (inout any SeededRandomNumberGenerator) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        counter.increment()
        let initialSeed = seed ?? Seed(stateA: 9, stateB: 0, stateC: 0, stateD: 0)
        var rng: any SeededRandomNumberGenerator = SplitMix64(seed: initialSeed.stateA)
        for trial in 0 ..< trials {
            let input = drawing(&rng)
            guard (try? await property(input)) == true else {
                return .failed(trialsRun: trial + 1, initialSeed: initialSeed, failingInput: input, thrownError: nil)
            }
        }
        return .passed(trialsRun: trials, initialSeed: initialSeed)
    }
}

/// A new engine that happens to use `Xoshiro`: implements only `drawing:`.
struct XoshiroDrawingBackend: DrawingPropertyBackend {
    let identifier = "xoshiro-drawing"

    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        drawing: @Sendable (inout any SeededRandomNumberGenerator) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input> {
        let initialSeed = seed ?? Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        var rng: any SeededRandomNumberGenerator = Xoshiro(
            seed: (initialSeed.stateA, initialSeed.stateB, initialSeed.stateC, initialSeed.stateD)
        )
        for trial in 0 ..< trials {
            let input = drawing(&rng)
            guard (try? await property(input)) == true else {
                return .failed(trialsRun: trial + 1, initialSeed: initialSeed, failingInput: input, thrownError: nil)
            }
        }
        return .passed(trialsRun: trials, initialSeed: initialSeed)
    }
}

/// Implements neither requirement. It compiles only because it opted into
/// `DrawingPropertyBackend`; as a plain `PropertyBackend` it would not.
struct NeitherBackend: DrawingPropertyBackend {
    let identifier = "neither"
}

// MARK: - Tests

/// `PropertyBackend.check(trials:seed:drawing:property:)` (4.13.0) and the two
/// defaults that let a backend implement either requirement.
@Suite("PropertyBackend — the drawing requirement")
struct BackendDrawingRequirementTests {

    private static let pairDraw: @Sendable (inout any SeededRandomNumberGenerator) -> (Int, Int) = { rng in
        (Int.random(in: 0 ... 999_999, using: &rng), Gen<Int>.int(in: 0 ... 999_999).run(using: &rng))
    }

    private static func options(_ index: Int, backend: any PropertyBackend) -> LawCheckOptions {
        LawCheckOptions(budget: .custom(trials: 6), seed: BackendSeedPinTests.seeds[index], backend: backend)
    }

    private static func recordUnary(options: LawCheckOptions) async -> (CheckResult, [Int]) {
        let recorder = DrawRecorder()
        let result = await runUnaryLaw(
            "Pin.unary",
            generator: Gen<Int>.int(in: 0 ... 999_999),
            options: options,
            property: { value in recorder.record(value) },
            formatCounterexample: { value, _ in "\(value)" }
        )
        return (result, recorder.values)
    }

    // MARK: The default backend

    /// Both requirements of the default backend replay a seed as the same draws.
    @Test(arguments: 0 ..< 3)
    func defaultBackendDrawsTheSameThroughEitherRequirement(index: Int) async {
        let recorder = DrawRecorder()
        _ = await SwiftPropertyBasedBackend().check(
            trials: 6,
            seed: BackendSeedPinTests.seeds[index],
            drawing: Self.pairDraw
        ) { pair in recorder.record(pair.0, pair.1) }
        #expect(recorder.values == BackendSeedPinTests.backendPins[index])
    }

    // MARK: A backend that implements only `sample:`

    /// The kit's driver now calls `drawing:`, so an existing backend is reached
    /// through the default. That default must write `Xoshiro`'s advanced state
    /// back after every draw: if it dropped it, all six trials would draw the
    /// first value, and the pins would not match.
    @Test(arguments: 0 ..< 3)
    func sampleOnlyBackendReplaysTheHistoricalDraws(index: Int) async {
        let backend = XoshiroOnlyBackend()
        let (result, values) = await Self.recordUnary(options: Self.options(index, backend: backend))
        #expect(backend.counter.calls == 1, "the law must run through the backend")
        #expect(result.seed == BackendSeedPinTests.seeds[index])
        #expect(result.environment.backendIdentity == "xoshiro-only")
        #expect(values == BackendSeedPinTests.unaryPins[index])

        let recorder = DrawRecorder()
        _ = await backend.check(
            trials: 6,
            seed: BackendSeedPinTests.seeds[index],
            drawing: Self.pairDraw
        ) { pair in recorder.record(pair.0, pair.1) }
        #expect(recorder.values == BackendSeedPinTests.backendPins[index])
    }

    /// The same, for a sampled space, whose draws keep an index.
    @Test(arguments: 0 ..< 3)
    func sampleOnlyBackendReplaysTheHistoricalSpaceDraws(index: Int) async {
        let recorder = DrawRecorder()
        _ = await runUnaryLaw(
            "Pin.space",
            source: .sampledFromSpace(Every.elements("value", in: Array(0 ..< 1_000))),
            options: Self.options(index, backend: XoshiroOnlyBackend()),
            property: { value in recorder.record(value) },
            formatCounterexample: { value, _ in "\(value)" }
        )
        #expect(recorder.values == BackendSeedPinTests.spacePins[index])
    }

    /// A `drawing` closure that swaps the generator for another type leaves no
    /// `Xoshiro` to write back. The default then continues the loop from a
    /// `Xoshiro` seeded from four words of the replacement, so the run stays
    /// deterministic: here each trial reseeds a `SplitMix64` from its own draw,
    /// and the next trial's draw is fixed by that.
    @Test(arguments: 0 ..< 3)
    func sampleOnlyBackendContinuesFromAReplacedGenerator(index: Int) async {
        let seed = BackendSeedPinTests.seeds[index]
        func draws() async -> [Int] {
            let recorder = DrawRecorder()
            _ = await XoshiroOnlyBackend().check(
                trials: 6,
                seed: seed,
                drawing: { rng in
                    let value = Int.random(in: 0 ... 999_999, using: &rng)
                    rng = SplitMix64(seed: UInt64(value))
                    return value
                },
                property: { value in recorder.record(value) }
            )
            return recorder.values
        }

        var xoshiro = Xoshiro(seed: (seed.stateA, seed.stateB, seed.stateC, seed.stateD))
        var expected = [Int.random(in: 0 ... 999_999, using: &xoshiro)]
        while expected.count < 6 {
            var replacement = SplitMix64(seed: UInt64(expected[expected.count - 1]))
            xoshiro = Xoshiro(seed: (replacement.next(), replacement.next(), replacement.next(), replacement.next()))
            expected.append(Int.random(in: 0 ... 999_999, using: &xoshiro))
        }

        let first = await draws()
        #expect(first == expected)
        #expect(await draws() == first)
        #expect(Set(first).count > 1)
    }

    // MARK: A backend that implements only `drawing:`

    /// A per-trial law draws from the engine's own generator: the values are
    /// the ones `SplitMix64` gives for the seed, not the `Xoshiro` pins.
    @Test(arguments: 0 ..< 3)
    func drawingOnlyBackendDrivesPerTrialLawsWithItsOwnGenerator(index: Int) async {
        let backend = SplitMixBackend()
        let (result, values) = await Self.recordUnary(options: Self.options(index, backend: backend))

        var expected = SplitMix64(seed: BackendSeedPinTests.seeds[index].stateA)
        let generator = Gen<Int>.int(in: 0 ... 999_999)
        let expectedValues = (0 ..< 6).map { _ in generator.run(using: &expected) }

        #expect(backend.counter.calls == 1)
        #expect(result.environment.backendIdentity == "splitmix")
        #expect(result.trials == 6)
        #expect(values == expectedValues)
        #expect(values != BackendSeedPinTests.unaryPins[index])
    }

    /// A public law suite runs its per-trial laws through the engine.
    @Test func drawingOnlyBackendRunsAPublicSuite() async throws {
        let backend = SplitMixBackend()
        let results = try await checkHashablePropertyLaws(
            using: Gen<Int>.int(in: -1_000 ... 1_000),
            options: LawCheckOptions(budget: .sanity, seed: BackendSeedPinTests.seeds[2], backend: backend)
        )
        #expect(results.allSatisfy { !$0.isViolation })
        #expect(backend.counter.calls > 0)
        #expect(results.allSatisfy { $0.environment.backendIdentity == "splitmix" })
    }

    /// Code that calls the `Xoshiro` form on a new engine still works. When the
    /// engine's generator is a `Xoshiro`, the closure runs on it directly and
    /// its state is written back, so the draws are the historical ones.
    @Test(arguments: 0 ..< 3)
    func sampleCallOnAXoshiroEngineReplaysTheHistoricalDraws(index: Int) async {
        let recorder = DrawRecorder()
        _ = await XoshiroDrawingBackend().check(
            trials: 6,
            seed: BackendSeedPinTests.seeds[index],
            sample: { rng in
                (Int.random(in: 0 ... 999_999, using: &rng), Gen<Int>.int(in: 0 ... 999_999).run(using: &rng))
            },
            property: { pair in recorder.record(pair.0, pair.1) }
        )
        #expect(recorder.values == BackendSeedPinTests.backendPins[index])
    }

    /// When the engine's generator is not a `Xoshiro`, each draw runs on a
    /// `Xoshiro` seeded from four of the engine's words: different values from
    /// the pins, but the same ones every time for a seed, and not one value
    /// repeated.
    @Test func sampleCallOnAnotherEngineIsDeterministic() async {
        func draws() async -> [Int] {
            let recorder = DrawRecorder()
            _ = await SplitMixBackend().check(
                trials: 6,
                seed: BackendSeedPinTests.seeds[2],
                sample: { rng in Int.random(in: 0 ... 999_999, using: &rng) },
                property: { value in recorder.record(value) }
            )
            return recorder.values
        }
        let first = await draws()
        let second = await draws()
        #expect(first.count == 6)
        #expect(first == second)
        #expect(Set(first).count > 1)
    }

    // MARK: Neither

    /// Implementing neither requirement compiles only under
    /// `DrawingPropertyBackend`, and the first call traps with a message naming
    /// the type. The test reads the message, not just the exit status.
    ///
    /// Not in the mutant corpus: without the trap the defaults recurse
    /// through async frames on the heap, which never overflows the stack and
    /// hangs the runner while the process grows by gigabytes a second.
    @Test func implementingNeitherRequirementTraps() async throws {
        let viaDrawing = try await #require(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            _ = await NeitherBackend().check(
                trials: 1,
                seed: nil,
                drawing: { rng in Int.random(in: 0 ... 9, using: &rng) },
                property: { _ in true }
            )
        }
        let viaSample = try await #require(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            _ = await NeitherBackend().check(
                trials: 1,
                seed: nil,
                sample: { rng in Int.random(in: 0 ... 9, using: &rng) },
                property: { _ in true }
            )
        }
        for result in [viaDrawing, viaSample] {
            let message = String(bytes: result.standardErrorContent, encoding: .utf8) ?? ""
            #expect(message.contains("NeitherBackend conforms to DrawingPropertyBackend but implements neither"))
        }
    }
}
