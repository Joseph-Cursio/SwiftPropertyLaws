import Foundation
import PropertyBased
@testable import PropertyLawKit
import Testing

/// Collects every input a law's `property` sees, in order.
final class DrawRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int] = []

    var values: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ newValues: Int...) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(contentsOf: newValues)
        return true
    }
}

/// The draws three historical seeds produce on the default backend, pinned as
/// literals.
///
/// The values were captured on `main` at 8316521, before `PropertyBackend` gained
/// `check(trials:seed:drawing:property:)` and the kit's sampling closures moved
/// from `inout Xoshiro` to `inout any SeededRandomNumberGenerator`. If one of
/// these fails, a stored seed now replays as different inputs, which the replay
/// fingerprint (PRD §4.6) does not detect, because the backend identity and the
/// Swift version are unchanged.
///
/// Each path the change touches has its own pin: the backend called directly,
/// a per-trial law through `PerLawDriver`, a sampled space (`SpaceSampler`) and
/// the draw pool (`DrawPoolDriver`). Six trials per seed, so a run that lost
/// the generator's state between trials would repeat its first draw.
@Suite("Backend seed pins")
struct BackendSeedPinTests {

    static let seeds: [Seed] = [
        Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4),
        Seed(stateA: 0x0123_4567_89AB_CDEF, stateB: 1, stateC: 2, stateD: 3),
        Seed(stateA: 0xDEAD_BEEF_CAFE_F00D, stateB: 0x0F0F_0F0F_0F0F_0F0F, stateC: 42, stateD: 7),
    ]

    static let options: @Sendable (Seed) -> LawCheckOptions = { seed in
        LawCheckOptions(budget: .custom(trials: 6), seed: seed)
    }

    /// Per seed: `Int.random(in:using:)` then `Gen.int(in:)` on each trial.
    static let backendPins: [[Int]] = [
        [0, 0, 65_917, 65_928, 32_959, 876_735, 459_494, 574_362, 157_459, 784_534, 68_675, 708_165],
        [0, 599_999, 599_999, 249_805, 592_133, 425_951, 806_673, 225_558, 498_369, 480_818, 621_920, 721_700],
        [823_529, 799_350, 787_677, 946_341, 796_852, 114_701, 997_394, 60_271, 532_223, 906_507, 847_318, 555_212],
    ]

    /// Per seed: one `Gen.int(in:)` draw per trial through `runUnaryLaw`.
    static let unaryPins: [[Int]] = [
        [0, 0, 65_917, 65_928, 32_959, 876_735],
        [0, 599_999, 599_999, 249_805, 592_133, 425_951],
        [823_529, 799_350, 787_677, 946_341, 796_852, 114_701],
    ]

    /// Per seed: one index-keeping draw per trial from a 1,000-element space.
    static let spacePins: [[Int]] = [
        [0, 0, 65, 65, 32, 876],
        [0, 599, 599, 249, 592, 425],
        [823, 799, 787, 946, 796, 114],
    ]

    /// Per seed: each pair the pool compared, earlier draw first.
    static let poolPins: [[Int]] = [
        [
            0, 0, 0, 65_917, 0, 65_917,
            0, 65_928, 65_917, 65_928, 65_917, 32_959,
            65_928, 32_959, 65_928, 876_735, 32_959, 876_735,
        ],
        [
            0, 599_999, 0, 599_999, 599_999, 599_999,
            599_999, 249_805, 599_999, 249_805, 599_999, 592_133,
            249_805, 592_133, 249_805, 425_951, 592_133, 425_951,
        ],
        [
            823_529, 799_350, 823_529, 787_677, 799_350, 787_677,
            799_350, 946_341, 787_677, 946_341, 787_677, 796_852,
            946_341, 796_852, 946_341, 114_701, 796_852, 114_701,
        ],
    ]

    @Test(arguments: 0 ..< 3)
    func backendCalledDirectly(index: Int) async {
        let recorder = DrawRecorder()
        _ = await SwiftPropertyBasedBackend().check(
            trials: 6,
            seed: Self.seeds[index],
            sample: { rng in
                (Int.random(in: 0 ... 999_999, using: &rng), Gen<Int>.int(in: 0 ... 999_999).run(using: &rng))
            },
            property: { pair in recorder.record(pair.0, pair.1) }
        )
        #expect(recorder.values == Self.backendPins[safe: index])
    }

    @Test(arguments: 0 ..< 3)
    func perTrialLaw(index: Int) async {
        let recorder = DrawRecorder()
        let result = await runUnaryLaw(
            "Pin.unary",
            generator: Gen<Int>.int(in: 0 ... 999_999),
            options: Self.options(Self.seeds[index]),
            property: { value in recorder.record(value) },
            formatCounterexample: { value, _ in "\(value)" }
        )
        #expect(result.seed == Self.seeds[index])
        #expect(recorder.values == Self.unaryPins[safe: index])
    }

    @Test(arguments: 0 ..< 3)
    func sampledSpace(index: Int) async {
        let recorder = DrawRecorder()
        _ = await runUnaryLaw(
            "Pin.space",
            source: .sampledFromSpace(Every.elements("value", in: Array(0 ..< 1_000))),
            options: Self.options(Self.seeds[index]),
            property: { value in recorder.record(value) },
            formatCounterexample: { value, _ in "\(value)" }
        )
        #expect(recorder.values == Self.spacePins[safe: index])
    }

    @Test(arguments: 0 ..< 3)
    func drawPool(index: Int) async {
        let recorder = DrawRecorder()
        var pooled = Self.options(Self.seeds[index])
        pooled.equalValuePairing = .recentDraws(window: 2)
        _ = await runEqualValueBinaryLaw(
            "Pin.pool",
            source: .sampling(Gen<Int>.int(in: 0 ... 999_999)),
            options: pooled,
            property: { first, second in recorder.record(first, second) },
            formatCounterexample: { first, second, _ in "\(first), \(second)" }
        )
        #expect(recorder.values == Self.poolPins[safe: index])
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
