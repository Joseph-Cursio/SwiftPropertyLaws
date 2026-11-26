@testable import PropertyLawAsync

/// An actor whose executor is a virtual-time run's own scheduler, so a task
/// from outside the run that calls it is enqueued on that scheduler directly,
/// not through the global enqueue hook.
actor SchedulerBoundActor {
    private let scheduler: VirtualTimeScheduler

    init(scheduler: VirtualTimeScheduler) {
        self.scheduler = scheduler
    }

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        scheduler.asUnownedSerialExecutor()
    }

    func touch() -> Int {
        1
    }
}
