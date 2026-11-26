import Foundation

/// The first sign that some of a run's work left its scheduler. Set from
/// whichever thread sees it; read by the scheduler's own thread.
final class EscapeEvidence: @unchecked Sendable {
    /// How the escape showed itself.
    enum Kind: Equatable, Sendable, CustomStringConvertible {
        /// A task of the run was enqueued from a thread outside the run: a
        /// continuation resumed by Dispatch, say, or the hop back from
        /// `MainActor` or a custom executor.
        case taskResumedFromOutside
        /// The body finished on a thread outside the run, with no enqueue for
        /// the hook to see: run there by a default actor that an outside task
        /// was holding, say.
        case bodyFinishedOutside
        /// The run's virtual clock was used from a thread outside the run.
        case clockUsedFromOutside
        /// A task of the run was run by another live run, which resumed it:
        /// the two share an actor or a continuation. Only the run whose task
        /// left reports it.
        case sharedWithAnotherRun

        var description: String {
            switch self {
            case .taskResumedFromOutside:
                return "a task of the run was resumed from another thread (a continuation resumed by Dispatch, "
                    + "or the hop back from MainActor or a custom executor)"

            case .bodyFinishedOutside:
                return "the body finished on another thread (an actor held outside the run ran it there)"

            case .clockUsedFromOutside:
                return "the virtual clock was used from another thread"

            case .sharedWithAnotherRun:
                return "a task of the run was run by another run going on at the same time (they share an "
                    + "actor or a continuation)"
            }
        }
    }

    private let lock = NSLock()
    private var first: Kind?

    var kind: Kind? {
        lock.lock()
        defer { lock.unlock() }
        return first
    }

    /// Keep the first sign; later ones add nothing to the verdict.
    func record(_ kind: Kind) {
        lock.lock()
        if first == nil {
            first = kind
        }
        lock.unlock()
    }
}
