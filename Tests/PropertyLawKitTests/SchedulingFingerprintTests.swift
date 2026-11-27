import Foundation
import PropertyBased
@testable import PropertyLawKit
import Testing

/// The kit side of `LawCheckOptions.scheduling`: the option, the fingerprint
/// field it feeds, the replay check, and the failure text.
///
/// The rule under test: `Environment.scheduling` records the strategy only when
/// the suite honours it (`schedulingIsInEffect`), stamping and checking share
/// `Environment.current(options:)`, and the strategy must match under every
/// relaxation. Under FIFO, and in every suite that ignores the option,
/// fingerprints and text are exactly what they were before the option existed.
struct SchedulingFingerprintTests {

    private static let relaxations: [EnvironmentRelaxation] = [.exact, .matchBackendOnly, .matchSwiftVersionOnly]

    private static let seed = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)

    /// Options for a virtual-time suite, which honours the strategy.
    private static func inEffect(_ scheduling: SchedulingStrategy) -> LawCheckOptions {
        var options = LawCheckOptions(budget: .sanity, scheduling: scheduling)
        options.schedulingIsInEffect = true
        return options
    }

    /// The fingerprint a virtual-time run under `scheduling` stores.
    private static func stored(_ scheduling: SchedulingStrategy) -> Environment {
        Environment.current(options: inEffect(scheduling))
    }

    private static func verify(
        stored: Environment,
        actual scheduling: SchedulingStrategy,
        relaxation: EnvironmentRelaxation
    ) throws {
        var options = inEffect(scheduling)
        options.expectedReplayEnvironment = stored
        options.replayRelaxation = relaxation
        try ReplayEnvironmentValidator.verify(options)
    }

    // MARK: - The strategy type

    @Test func strategiesHaveStableIdentifiersAndDisplayNames() {
        #expect(SchedulingStrategy.fifo.identifier == nil)
        #expect(SchedulingStrategy.seeded.identifier == "seeded/1")
        #expect(SchedulingStrategy.fifo.description == "fifo")
        #expect(SchedulingStrategy.seeded.description == "seeded")
        #expect(SchedulingStrategy.fifo != .seeded)
    }

    @Test func optionsDefaultToFIFOAndNotInEffect() {
        let options = LawCheckOptions()
        #expect(options.scheduling == .fifo)
        #expect(options.schedulingIsInEffect == false)
        #expect(LawCheckOptions(scheduling: .seeded).scheduling == .seeded)
    }

    // MARK: - Stamping

    @Test func fifoFingerprintIsTheBackendFingerprint() {
        #expect(Self.stored(.fifo) == Environment.current(backend: SwiftPropertyBasedBackend()))
        #expect(Self.stored(.fifo).scheduling == nil)
        #expect(Self.stored(.seeded).scheduling == "seeded/1")
    }

    /// `.seeded` set on a suite that does not honour it — every suite outside
    /// virtual time — records nothing.
    @Test func seededNotInEffectRecordsNoStrategy() {
        let options = LawCheckOptions(scheduling: .seeded)
        #expect(Environment.current(options: options) == Environment.current(backend: options.backend))
        #expect(Environment.current(options: options).scheduling == nil)
    }

    /// Every driver stamps with `current(options:)`, so a driver left on
    /// `current(backend:)` would drop the strategy here.
    @Test func everyDriverStampsTheStrategyInEffect() async throws {
        let options = Self.inEffect(.seeded)
        let perTrial = await runUnaryLaw(
            "Scheduling.perTrial",
            generator: Gen<Int>.int(in: 0 ... 9),
            options: options,
            property: { _ in true },
            formatCounterexample: { value, _ in "\(value)" }
        )
        let aggregate = await AggregateDriver.run(
            protocolLaw: "Scheduling.aggregate", tier: .strict, options: options
        ) { _, _ in .passed }
        let walk = try await checkEveryCase(
            of: Every.elements("x", in: [1, 2, 3]), law: "Scheduling.walk", options: options
        ) { _ in true }
        var pooledOptions = options
        pooledOptions.equalValuePairing = .everyPairOfDraws
        let pooled = await runEqualValueBinaryLaw(
            "Scheduling.pooled",
            source: .sampling(Gen<Int>.int(in: 0 ... 9)),
            options: pooledOptions,
            property: { lhs, rhs in lhs == rhs || lhs != rhs },
            formatCounterexample: { lhs, rhs, _ in "\(lhs), \(rhs)" }
        )
        #expect(pooled.pairedDraws != nil, "the pooled law must reach DrawPoolDriver")
        for result in [perTrial, aggregate, pooled] + walk {
            #expect(result.environment.scheduling == "seeded/1", "\(result.protocolLaw)")
        }
    }

    /// A sync law run with `.seeded` draws, fingerprints and reports exactly as
    /// under `.fifo`: the option is ignored outside virtual time.
    @Test func aSyncLawUnderSeededKeepsItsFIFOFingerprintAndText() async {
        func run(_ scheduling: SchedulingStrategy) async -> CheckResult {
            await runUnaryLaw(
                "Scheduling.fails",
                generator: Gen<Int>.int(in: 0 ... 999),
                options: LawCheckOptions(budget: .sanity, seed: Self.seed, scheduling: scheduling),
                property: { $0 < 500 },
                formatCounterexample: { value, _ in "x = \(value)" }
            )
        }
        let fifo = await run(.fifo)
        let seeded = await run(.seeded)
        #expect(fifo.isViolation)
        #expect(seeded == fifo)
        #expect(seeded.environment.scheduling == nil)
        #expect(ViolationFormatter.format(seeded) == ViolationFormatter.format(fifo))
        #expect(!ViolationFormatter.format(seeded).contains("scheduling"))
    }

    @Test func aSyncSuiteUnderSeededRecordsNoStrategy() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity, scheduling: .seeded)
        )
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { $0.environment.scheduling == nil })
    }

    // MARK: - Checking: four stored/actual combinations under each relaxation

    @Test(arguments: relaxations)
    func fifoStoredReplaysUnderFIFO(relaxation: EnvironmentRelaxation) throws {
        try Self.verify(stored: Self.stored(.fifo), actual: .fifo, relaxation: relaxation)
        // And a suite outside virtual time, which never honours the option.
        var options = LawCheckOptions(scheduling: .seeded)
        options.expectedReplayEnvironment = Self.stored(.fifo)
        options.replayRelaxation = relaxation
        try ReplayEnvironmentValidator.verify(options)
    }

    @Test(arguments: relaxations)
    func fifoStoredIsRefusedUnderSeeded(relaxation: EnvironmentRelaxation) {
        let mismatch = #expect(throws: ReplayEnvironmentMismatch.self) {
            try Self.verify(stored: Self.stored(.fifo), actual: .seeded, relaxation: relaxation)
        }
        #expect(mismatch?.expected.scheduling == nil)
        #expect(mismatch?.actual.scheduling == "seeded/1")
    }

    @Test(arguments: relaxations)
    func seededStoredReplaysUnderSeeded(relaxation: EnvironmentRelaxation) throws {
        try Self.verify(stored: Self.stored(.seeded), actual: .seeded, relaxation: relaxation)
    }

    @Test(arguments: relaxations)
    func seededStoredIsRefusedUnderFIFO(relaxation: EnvironmentRelaxation) {
        let mismatch = #expect(throws: ReplayEnvironmentMismatch.self) {
            try Self.verify(stored: Self.stored(.seeded), actual: .fifo, relaxation: relaxation)
        }
        #expect(mismatch?.expected.scheduling == "seeded/1")
        #expect(mismatch?.actual.scheduling == nil)
    }

    /// The relaxations still relax what they always did once the strategy matches.
    @Test func relaxationsStillIgnoreDriftWhenTheStrategyMatches() {
        let live = Self.stored(.seeded)
        let otherToolchain = Environment(
            swiftVersion: "1.0", backendIdentity: live.backendIdentity,
            generatorSchemaHash: live.generatorSchemaHash, scheduling: "seeded/1"
        )
        let otherBackend = Environment(
            swiftVersion: live.swiftVersion, backendIdentity: "imaginary-backend",
            generatorSchemaHash: live.generatorSchemaHash, scheduling: "seeded/1"
        )
        #expect(EnvironmentRelaxation.matchBackendOnly.matches(expected: otherToolchain, actual: live))
        #expect(EnvironmentRelaxation.matchSwiftVersionOnly.matches(expected: otherBackend, actual: live))
        #expect(EnvironmentRelaxation.exact.matches(expected: otherToolchain, actual: live) == false)
    }

    // MARK: - Old fingerprints

    @Test func threeArgumentFingerprintEqualsOneWithNilScheduling() {
        let old = Environment(swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash")
        let new = Environment(
            swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash", scheduling: nil
        )
        #expect(old.scheduling == nil)
        #expect(old == new)
        #expect(old.hashValue == new.hashValue)
    }

    @Test func jsonWithoutTheSchedulingKeyDecodesAsFIFO() throws {
        let json = Data(#"{"swiftVersion":"6.2","backendIdentity":"backend","generatorSchemaHash":"hash"}"#.utf8)
        let decoded = try JSONDecoder().decode(Environment.self, from: json)
        #expect(decoded == Environment(swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash"))
        #expect(decoded.scheduling == nil)
    }

    @Test func fifoEncodesWithoutTheKeyAndSeededRoundTrips() throws {
        let fifo = Environment(swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash")
        let fifoJSON = try #require(String(data: JSONEncoder().encode(fifo), encoding: .utf8))
        #expect(!fifoJSON.contains("scheduling"), "a FIFO fingerprint must encode as it did before the field")
        let seeded = Environment(
            swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash", scheduling: "seeded/1"
        )
        let roundTripped = try JSONDecoder().decode(Environment.self, from: JSONEncoder().encode(seeded))
        #expect(roundTripped == seeded)
    }

    // MARK: - Mismatch description

    @Test func mismatchDescriptionNamesTheStrategyOnlyWhenItDiffers() {
        let fifo = Self.stored(.fifo)
        let seeded = Self.stored(.seeded)
        #expect(ReplayEnvironmentMismatch(expected: fifo, actual: seeded).description
            == "ReplayEnvironmentMismatch — scheduling: fifo → seeded/1")
        #expect(ReplayEnvironmentMismatch(expected: seeded, actual: fifo).description
            == "ReplayEnvironmentMismatch — scheduling: seeded/1 → fifo")
        let drifted = Environment(
            swiftVersion: "1.0", backendIdentity: seeded.backendIdentity,
            generatorSchemaHash: seeded.generatorSchemaHash, scheduling: "seeded/1"
        )
        let sameStrategy = ReplayEnvironmentMismatch(expected: drifted, actual: seeded).description
        #expect(sameStrategy.contains("swiftVersion: 1.0 →"))
        #expect(!sameStrategy.contains("scheduling:"))
    }

    // MARK: - Failure text

    private static func result(scheduling: String?, coverage: SpaceCoverage? = nil) -> CheckResult {
        CheckResult(
            protocolLaw: "Lifetime.law",
            tier: .strict,
            trials: 7,
            seed: seed,
            environment: Environment(
                swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash", scheduling: scheduling
            ),
            outcome: .failed(counterexample: "source = [1]; leaked"),
            coverage: coverage
        )
    }

    private static func replayLine(_ text: String) -> String? {
        text.split(separator: "\n").map(String.init).first { $0.contains("Replay with seed:") }
    }

    @Test(arguments: [false, true])
    func fifoTextIsUnchangedWhateverTheHashing(deterministicHashing: Bool) {
        let fifo = Self.result(scheduling: nil)
        let text = ViolationFormatter.format(fifo, deterministicHashing: deterministicHashing)
        #expect(text == ViolationFormatter.format(fifo))
        #expect(Self.replayLine(text) == "  Replay with seed: \(Self.seed.description)")
        #expect(!text.contains("scheduling"))
        #expect(!text.contains("SWIFT_DETERMINISTIC_HASHING"))
    }

    @Test func seededTextNamesTheStrategyAndWarnsWithoutDeterministicHashing() {
        let text = ViolationFormatter.format(Self.result(scheduling: "seeded/1"), deterministicHashing: false)
        #expect(Self.replayLine(text) == """
              Replay with seed: \(Self.seed.description) (scheduling: seeded/1; SWIFT_DETERMINISTIC_HASHING \
            is not set to 1, so a replay may differ if the code under test iterates a Dictionary or Set)
            """)
    }

    @Test func seededTextWithDeterministicHashingNamesOnlyTheStrategy() {
        let text = ViolationFormatter.format(Self.result(scheduling: "seeded/1"), deterministicHashing: true)
        #expect(Self.replayLine(text) == "  Replay with seed: \(Self.seed.description) (scheduling: seeded/1)")
    }

    /// The production entry point reads the process's own setting.
    @Test func productionFormatReadsTheProcessSetting() {
        let seeded = Self.result(scheduling: "seeded/1")
        let processSetting = ViolationFormatter.processHasDeterministicHashing
        #expect(ViolationFormatter.format(seeded)
            == ViolationFormatter.format(seeded, deterministicHashing: processSetting))
        #expect(ViolationFormatter.processHasDeterministicHashing
            == ViolationFormatter.hasDeterministicHashing(ProcessInfo.processInfo.environment))
    }

    /// Only the exact value `"1"` turns deterministic hashing on.
    @Test func onlyTheValueOneCountsAsDeterministicHashing() {
        let name = "SWIFT_DETERMINISTIC_HASHING"
        #expect(ViolationFormatter.hasDeterministicHashing([name: "1"]))
        #expect(!ViolationFormatter.hasDeterministicHashing([name: "0"]))
        #expect(!ViolationFormatter.hasDeterministicHashing([name: "true"]))
        #expect(!ViolationFormatter.hasDeterministicHashing([:]))
    }

    @Test func aWalkStillOffersNoSeed() {
        let text = ViolationFormatter.format(
            Self.result(scheduling: "seeded/1", coverage: SpaceCoverage(casesRun: 3, spaceSize: 8)),
            deterministicHashing: false
        )
        #expect(Self.replayLine(text) == nil)
        #expect(text.contains("Deterministic walk"))
    }
}
