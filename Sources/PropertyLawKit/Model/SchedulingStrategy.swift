/// The order in which a virtual-time run picks its next runnable job.
///
/// Only laws that run in virtual time honour it: today
/// `checkTimedAsyncSequencePropertyLaws` and `checkAsyncLifetimePropertyLaws`.
/// Every other law ignores it, draws exactly what it draws under ``fifo``, and
/// records the same environment fingerprint and failure text as under ``fifo``.
///
/// Under ``seeded`` each trial draws one schedule seed from the run's generator,
/// right after its input, and that seed picks among the runnable jobs. So
/// `CheckResult.seed` replays the whole run, schedules included. Trials after
/// the first draw different inputs than they would under ``fifo``, which is why
/// the strategy is part of the replay fingerprint (`Environment.scheduling`) and
/// must match under every `EnvironmentRelaxation`.
///
/// A seeded replay needs the same toolchain, build configuration and OS: the
/// compiled code decides where the scheduling points are, and so which jobs a
/// seed chooses between. It also needs code under test that does not iterate a
/// `Dictionary` or `Set` in an order that matters, unless the process runs with
/// `SWIFT_DETERMINISTIC_HASHING=1`.
///
/// A struct rather than an enum, so a later strategy is an addition, not a
/// source break for code that switches over the cases.
public struct SchedulingStrategy: Sendable, Hashable, CustomStringConvertible {
    private enum Kind: Sendable, Hashable {
        case fifo
        case seeded
    }

    private let kind: Kind

    private init(_ kind: Kind) {
        self.kind = kind
    }

    /// Runnable jobs run in the order they were enqueued. The default, and the
    /// order every virtual-time run used before this option existed.
    public static let fifo = Self(.fifo)

    /// Each trial draws a schedule seed from the run's generator, and the seed
    /// picks which runnable job goes next. See the type's documentation for
    /// what replaying one needs.
    public static let seeded = Self(.seeded)

    /// For display: `"fifo"` or `"seeded"`. Not stable; the fingerprint uses
    /// ``identifier``.
    public var description: String {
        switch kind {
        case .fifo: return "fifo"
        case .seeded: return "seeded"
        }
    }

    /// The stable name recorded in `Environment.scheduling`: `nil` for ``fifo``,
    /// so fingerprints stored before the option existed still match, and
    /// `"seeded/1"` for ``seeded``.
    ///
    /// The version after the slash is bumped by any change to how a seed picks
    /// jobs (the random number generator, the mapping from a draw to a job, the
    /// rule for a single candidate, the candidate set, the removal order), so a
    /// stored seeded fingerprint never silently replays a different schedule.
    public var identifier: String? {
        switch kind {
        case .fifo: return nil
        case .seeded: return "seeded/1"
        }
    }
}
