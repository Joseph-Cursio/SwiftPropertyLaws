import Foundation

/// The order in which a virtual-time run ran its jobs, one step per job.
///
/// Nothing in it is an address: a job is named by the pending jobs it was
/// picked from and its position among them, in enqueue order, and by the
/// ordinal of its task within the run, in the order the run first saw each
/// task. So a run of the same body under the same order and seed records the
/// same steps in every run and process, as long as nothing outside the run
/// adds jobs (an escape) and the code under test does not iterate a
/// `Dictionary` or `Set` in an order that matters.
///
/// Steps cover the drive loop and teardown. The run's last drain, which only
/// runs jobs handed back from other threads, is not recorded: when those
/// jobs arrive depends on real time. ``verdictStep`` marks where the drive
/// loop decided the run's outcome; steps after it are teardown.
final class ScheduleTrace: @unchecked Sendable {
    /// One job the scheduler ran.
    struct Step: Equatable, Sendable, CustomStringConvertible {
        /// How many jobs were pending when this one was picked.
        let pending: Int
        /// Its position among them, in enqueue order: 0 is the oldest.
        let picked: Int
        /// The ordinal of its task within the run, from 0 in first-seen
        /// order, or `nil` for a job that belongs to no task, such as an
        /// actor's processing job.
        let task: Int?

        var description: String {
            "\(picked)/\(pending):\(task.map(String.init) ?? "-")"
        }
    }

    private let lock = NSLock()
    private var recorded: [Step] = []
    private var boundary: Int?

    var steps: [Step] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// How many steps ran before the drive loop decided the run's outcome,
    /// or `nil` if the run never got that far.
    var verdictStep: Int? {
        lock.lock()
        defer { lock.unlock() }
        return boundary
    }

    /// The steps up to the verdict: what a replay must reproduce exactly.
    var stepsBeforeVerdict: [Step] {
        lock.lock()
        defer { lock.unlock() }
        return Array(recorded.prefix(boundary ?? recorded.count))
    }

    /// The steps where there was a choice to make.
    var choices: [Step] {
        steps.filter { $0.pending > 1 }
    }

    func record(_ step: Step) {
        lock.lock()
        recorded.append(step)
        lock.unlock()
    }

    func markVerdict() {
        lock.lock()
        if boundary == nil {
            boundary = recorded.count
        }
        lock.unlock()
    }
}
