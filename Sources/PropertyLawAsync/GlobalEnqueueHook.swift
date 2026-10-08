import Foundation

/// The Swift runtime's global-executor enqueue hook, installed while any
/// virtual-time run is active and removed when the last one ends.
///
/// **Why a runtime hook at all.** A virtual-time run has to own every job of
/// the code under test, and that code spawns tasks of its own: `debounce`
/// runs its machinery in an unstructured `Task {}`. A task-executor
/// preference would be the scoped way to capture them, but an unstructured
/// task does not inherit one — measured on Swift 6.4: a `Task {}`, a
/// `Task.detached` and the group children of either all run on the global
/// executor, and only structured children of the preferring task stay put.
/// The global enqueue hook is the one interception point that sees them. It
/// is reached by symbol lookup, exactly as swift-concurrency-extras'
/// `withMainSerialExecutor` reaches it.
///
/// **Why it does not serialise the process.** That function sends *every*
/// global job to the main thread. This hook diverts only jobs enqueued from
/// a virtual-time scheduler's own thread and hands the rest to the runtime
/// untouched, so tests running alongside keep their concurrency.
///
/// Another hook already in the slot is refused rather than replaced: taking
/// it would silently change scheduling for whoever installed it.
final class GlobalEnqueueHook: @unchecked Sendable {
    typealias Original = @convention(thin) (UnownedJob) -> Void
    typealias Hook = @convention(thin) (UnownedJob, Original) -> Void

    static let shared = GlobalEnqueueHook(slot: runtimeSlot)

    nonisolated(unsafe) private static let runtimeSlot: UnsafeMutablePointer<Hook?>? =
        dlsym(dlopen(nil, RTLD_NOW), "swift_task_enqueueGlobal_hook")?
            .assumingMemoryBound(to: Hook?.self)

    nonisolated(unsafe) private let slot: UnsafeMutablePointer<Hook?>?
    private let lock = NSLock()
    private var activeRuns = 0
    private var installedBits: UInt = 0

    /// - Parameter slot: where the hook lives. The runtime's own for
    ///   ``shared``; tests pass one of their own so they can exercise the
    ///   refusal and reference counting without touching the process.
    init(slot: UnsafeMutablePointer<Hook?>?) {
        self.slot = slot
    }

    var isInstalled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeRuns > 0
    }

    /// Whether the slot still holds this hook. False once anything else has
    /// replaced it, at which point a run can no longer trust an empty queue.
    var isIntact: Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let slot, activeRuns > 0 else { return false }
        return Self.bits(of: slot) == installedBits
    }

    func acquire() throws {
        lock.lock()
        defer { lock.unlock() }
        guard let slot else { throw VirtualTimeError.hookUnavailable }
        if activeRuns == 0 {
            guard slot.pointee == nil else { throw VirtualTimeError.foreignHookInstalled }
            slot.pointee = { job, original in
                if let scheduler = VirtualTimeScheduler.current {
                    scheduler.schedule(job)
                } else {
                    original(job)
                }
            }
            installedBits = Self.bits(of: slot)
        } else if Self.bits(of: slot) != installedBits {
            throw VirtualTimeError.foreignHookInstalled
        }
        activeRuns += 1
    }

    func release() {
        lock.lock()
        defer { lock.unlock() }
        activeRuns -= 1
        // Only take out what this put in: a hook installed over this one
        // belongs to someone else, who will restore the slot themselves.
        if activeRuns == 0, let slot, Self.bits(of: slot) == installedBits {
            slot.pointee = nil
        }
    }

    /// The slot's raw contents. Thin function values have no `==`, and the
    /// question is only ever "is this still the pointer that was stored?".
    private static func bits(of slot: UnsafeMutablePointer<Hook?>) -> UInt {
        UnsafeRawPointer(slot).load(as: UInt.self)
    }
}
