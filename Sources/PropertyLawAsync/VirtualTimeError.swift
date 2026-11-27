import Foundation

/// Why a virtual-time run ended without its body's result.
enum VirtualTimeError: Error, Equatable, CustomStringConvertible {
    /// Every task was blocked, nothing was asleep, and no work came back from
    /// outside the run within the grace window.
    case deadlock(stuckAt: Duration)
    /// Some of the run's work ran outside its scheduler, so its verdict
    /// cannot be trusted.
    case escaped(at: Duration, evidence: EscapeEvidence.Kind)
    /// The next sleeper's deadline lies beyond the run's horizon.
    case horizonExceeded(horizon: Duration, nextDeadline: Duration)
    /// The runtime's global enqueue hook could not be found.
    case hookUnavailable
    /// Another global enqueue hook was installed — `withMainSerialExecutor`,
    /// for one — so this run cannot see its own tasks.
    case foreignHookInstalled
    /// `runInVirtualTime` was called from inside a run. Runs do not nest.
    case nestedRun
    /// The run ran `steps` jobs in all without reaching a verdict: a task that
    /// re-enqueues itself forever, such as a `Task.yield()` loop, or one that
    /// settles in a loop.
    /// Its tasks are abandoned, so an actor one of them held can stay unusable
    /// for the rest of the process.
    case stepLimitExceeded(steps: Int)

    var description: String {
        switch self {
        case .deadlock(let now):
            return "virtual-time deadlock at \(now), or work that escaped the scheduler: every task is blocked, "
                + "none is sleeping on the clock, and nothing came back from outside the run within "
                + "\(VirtualTimeScheduler.graceWindow)"

        case let .escaped(now, evidence):
            return "work escaped the virtual-time scheduler by \(now): \(evidence). A real sleep, MainActor, "
                + "a custom executor, Task.yield() inside an actor or a callback from another thread can run "
                + "outside virtual time, so the run's result cannot be trusted"

        case let .horizonExceeded(horizon, nextDeadline):
            return "virtual time would pass its horizon of \(horizon): the next "
                + "sleeper wakes at \(nextDeadline)"

        case .hookUnavailable:
            return "the Swift runtime's global enqueue hook was not found, so "
                + "virtual time cannot capture the tasks under test"

        case .foreignHookInstalled:
            return "another global enqueue hook is installed (is this running "
                + "inside withMainSerialExecutor?); virtual time cannot share it"

        case .nestedRun:
            return "runInVirtualTime was called from inside a virtual-time run; "
                + "runs do not nest"

        case .stepLimitExceeded(let steps):
            return "the virtual-time run ran \(steps) jobs without reaching a verdict: a task that re-enqueues "
                + "itself forever, such as a Task.yield() loop, or that settles in a loop keeps the run from ending"
        }
    }
}
