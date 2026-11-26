import Foundation

/// How a virtual-time run picks its next job when more than one is pending.
enum JobOrder: Sendable, Equatable {
    /// The oldest first: the order the jobs were enqueued in.
    case fifo
    /// A choice drawn from a generator seeded with this value, so each seed
    /// explores one interleaving and gives the same one every time.
    case seeded(UInt64)
}

/// SplitMix64, as the schedule-explorer prototype and the swift-async-algorithms
/// fork used: small, fast, and the same on every platform, which a schedule seed
/// needs. Not the run's input generator, which stays the backend's.
struct SplitMix64: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}

/// A run's pending jobs, in the order they were enqueued, and the rule that
/// picks the next one.
///
/// **The pick, which a stored schedule seed depends on.** With one job
/// pending it is taken and nothing is drawn, so a seed's draws go only to real
/// choices, and a job added where there was no choice shifts no later draw.
/// With `n > 1` pending, FIFO takes the oldest; a seeded order takes the one at
/// `next() % n` in enqueue order (the modulo's bias is negligible for the few
/// jobs ever pending) and removes it, leaving the rest in enqueue order.
/// Sleepers are never candidates: they wake one at a time when the queue is
/// empty. Changing any of this changes what a stored seed replays, so it bumps
/// the version in `SchedulingStrategy`'s identifier.
///
/// Jobs can be appended from other threads (an escape coming back), so every
/// access takes the lock. Generic so tests can check the rule on plain values;
/// the scheduler queues `UnownedJob`s.
final class JobQueue<Job>: @unchecked Sendable {
    /// The job picked, how many were pending, and its position among them.
    struct Pick {
        let job: Job
        let pending: Int
        let picked: Int
    }

    private let lock = NSLock()
    private var jobs: [Job] = []
    private var head = 0
    /// `nil` under FIFO, which never draws.
    private var generator: SplitMix64?

    init(order: JobOrder) {
        if case .seeded(let seed) = order {
            generator = SplitMix64(seed: seed)
        }
    }

    func append(_ job: Job) {
        lock.lock()
        jobs.append(job)
        lock.unlock()
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return head == jobs.count
    }

    func next() -> Pick? {
        lock.lock()
        defer { lock.unlock() }
        guard head < jobs.count else {
            jobs.removeAll(keepingCapacity: true)
            head = 0
            return nil
        }
        let pending = jobs.count - head
        var offset = 0
        if pending > 1, var drawing = generator {
            offset = Int(drawing.next() % UInt64(pending))
            generator = drawing
        }
        let job: Job
        if offset == 0 {
            job = jobs[head]
            head += 1
        } else {
            job = jobs.remove(at: head + offset)
        }
        return Pick(job: job, pending: pending, picked: offset)
    }
}
