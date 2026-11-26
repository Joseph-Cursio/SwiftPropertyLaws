import Foundation

/// Which live run each task belongs to, by task ID, for every run in the
/// process.
///
/// A task that escaped its run comes back by being enqueued from a thread
/// outside the run, where `VirtualTimeScheduler.current` is `nil`. The hook
/// asks this registry whose task it is, and hands it back to that run, which
/// then reports the escape. A run claims each task the first time one of its
/// jobs runs, and forgets them all when it ends.
///
/// A run claims only tasks it created. A job runs on a run's thread whenever
/// it is enqueued from there, including the job of an outside task the run
/// resumes; claiming that task would turn its own later trip to Dispatch
/// into an escape of the run. Task IDs only grow, so a task created before
/// the run's root has a smaller ID and is left alone. An outside task
/// created after the root and resumed by the run is still claimed.
///
/// Runs can be concurrent and a foreign thread has no scheduler of its own,
/// so this is one locked table for the process. While no run is live it is
/// empty, and the hook's lookup costs a lock and nothing more.
final class RunRegistry: @unchecked Sendable {
    static let shared = RunRegistry()

    /// What a run's claim on a task came to.
    enum Claim {
        case claimed
        /// The task is older than the run's root, so not the run's.
        case createdBeforeTheRun
        /// Another live run already owns the task, so the two runs share it.
        case ownedBy(VirtualTimeScheduler)
    }

    private let lock = NSLock()
    private var owners: [UInt64: VirtualTimeScheduler] = [:]

    /// Claim task `id` for `scheduler`, whose root task's ID is `floor`.
    /// The first live run to claim a task keeps it.
    func claim(_ id: UInt64, for scheduler: VirtualTimeScheduler, createdSince floor: UInt64) -> Claim {
        lock.lock()
        defer { lock.unlock() }
        if let owner = owners[id], owner !== scheduler {
            return .ownedBy(owner)
        }
        guard id >= floor else { return .createdBeforeTheRun }
        owners[id] = scheduler
        return .claimed
    }

    /// Hand `job` back to the run that owns its task, if one is live, and
    /// say whether it did. Done under the lock, so a run that is forgetting
    /// its tasks either gets the job before it drains for the last time or
    /// never sees it.
    func returnToOwner(_ job: UnownedJob) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !owners.isEmpty, let id = TaskIdentity.id(of: job), let owner = owners[id] else { return false }
        owner.takeBack(job)
        return true
    }

    func forget(_ ids: Set<UInt64>, of scheduler: VirtualTimeScheduler) {
        lock.lock()
        for id in ids where owners[id] === scheduler {
            owners[id] = nil
        }
        lock.unlock()
    }
}
