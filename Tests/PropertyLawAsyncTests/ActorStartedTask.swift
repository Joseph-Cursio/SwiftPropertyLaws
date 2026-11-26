/// A default actor that starts a task isolated to itself. The task's first
/// job runs inside the actor's processing job, which belongs to no task, and
/// the task leaves the actor without an enqueue, so a run first sees the
/// task's own ID only when the task is next resumed.
actor ActorStartedTask {
    private var started = 0

    /// Start the task: it parks in `slot`, then, once resumed, runs `work`.
    func start(parkingIn slot: ContinuationSlot, then work: @escaping @Sendable () async -> Void) {
        Task {
            started += 1
            await slot.park()
            await work()
        }
    }
}
