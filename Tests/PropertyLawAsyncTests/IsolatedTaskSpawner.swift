/// A default actor whose method starts a task isolated to it, so the actor
/// must schedule a processing job of its own: a job on the global executor
/// that belongs to no task.
actor IsolatedTaskSpawner {
    private var count = 0

    func spawn() async {
        let task = Task {
            count += 1
        }
        await task.value
    }
}
