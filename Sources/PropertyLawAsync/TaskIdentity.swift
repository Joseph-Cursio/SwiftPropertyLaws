import Foundation

/// The runtime's ID for the task a job belongs to: unique for the life of the
/// process and never reused, unlike a job's address, which a non-task job
/// such as an actor's processing job can share with a later one.
enum TaskIdentity {
    private typealias GetJobTaskID = @convention(thin) (UnownedJob) -> UInt64

    /// `swift_task_getJobTaskId`, the function behind `UnownedJob.description`,
    /// reached by symbol lookup as ``GlobalEnqueueHook`` reaches its slot.
    private static let getJobTaskID: GetJobTaskID? =
        dlsym(dlopen(nil, RTLD_NOW), "swift_task_getJobTaskId").map { unsafeBitCast($0, to: GetJobTaskID.self) }

    /// The job's task ID, or `nil` for a job that belongs to no task.
    static func id(of job: UnownedJob) -> UInt64? {
        let id = getJobTaskID?(job) ?? parsedID(of: job)
        return id == 0 ? nil : id
    }

    /// The same ID read from `UnownedJob(id: N)`, the job's public
    /// description, should the symbol lookup ever fail.
    private static func parsedID(of job: UnownedJob) -> UInt64 {
        let text = job.description
        guard let start = text.range(of: "(id: ")?.upperBound,
              let end = text[start...].firstIndex(of: ")")
        else { return 0 }
        return UInt64(text[start ..< end]) ?? 0
    }
}
