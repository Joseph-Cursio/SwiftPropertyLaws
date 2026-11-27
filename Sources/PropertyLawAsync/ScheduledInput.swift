import PropertyBased
import PropertyLawKit

/// One trial's input and, under ``SchedulingStrategy/seeded``, the seed of
/// the order its virtual-time run picks jobs in.
struct ScheduledInput<Value: Sendable>: Sendable {
    let value: Value
    /// `nil` under FIFO.
    let schedule: UInt64?

    var order: JobOrder {
        schedule.map(JobOrder.seeded) ?? .fifo
    }

    /// Ends a counterexample under a seeded strategy, after everything else,
    /// so a counterexample still starts `source = [...]; ` and its first
    /// clause is unchanged.
    var scheduleSuffix: String {
        schedule.map { "; schedule seed \($0)" } ?? ""
    }

    /// The same schedule for a smaller input, so a shrunk counterexample
    /// replays under the seed that found it.
    func with(_ smaller: Value) -> Self {
        Self(value: smaller, schedule: schedule)
    }
}

/// Each trial's input from `generator` and then, under a seeded strategy, one
/// schedule seed from the same generator, so `CheckResult.seed` replays both.
/// Whether to draw it is decided here, from `options`, never by drawing, so a
/// FIFO run consumes exactly the words it always has.
func scheduledSampler<Value: Sendable, Shrinker: SendableSequenceType>(
    _ generator: Generator<Value, Shrinker>,
    options: LawCheckOptions
) -> InputSource<ScheduledInput<Value>> {
    let seeded = options.scheduling == .seeded
    return .sampled { rng in
        let value = generator.run(using: &rng)
        return ScheduledInput(value: value, schedule: seeded ? rng.next() : nil)
    }
}

/// The options a virtual-time suite runs under: the scheduling strategy is in
/// effect, so the suite's fingerprint records it and replay checks it. Set on
/// the options passed to `runPropertyLawSuite`, which checks the fingerprint,
/// as well as on each law's, which stamps it.
func inVirtualTime(_ options: LawCheckOptions) -> LawCheckOptions {
    var options = options
    options.schedulingIsInEffect = true
    return options
}
