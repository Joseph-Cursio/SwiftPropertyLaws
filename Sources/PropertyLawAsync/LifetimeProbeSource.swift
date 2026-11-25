import Foundation

/// The error a ``LifetimeProbeSource`` fails with. The failure law expects the
/// operator under test to deliver this error, not swallow or replace it.
struct LifetimeProbeFailure: Error, Equatable, CustomStringConvertible {
    var description: String { "the lifetime probe's upstream failure" }
}

/// What one trial's probe source saw: iterators made and released, and
/// whether it reached its failure.
final class LifetimeProbe: @unchecked Sendable {
    /// What the probe has seen so far.
    struct Snapshot: Sendable, Equatable {
        let made: Int
        let released: Int
        /// Whether a source threw its failure: an operator that stops reading
        /// before the end never makes it fail, and owes its consumer nothing.
        let failed: Bool
    }

    private let lock = NSLock()
    private var made = 0
    private var released = 0
    private var failed = false

    var snapshot: Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(made: made, released: released, failed: failed)
    }

    func recordMade() {
        lock.lock()
        made += 1
        lock.unlock()
    }

    func recordReleased() {
        lock.lock()
        released += 1
        lock.unlock()
    }

    func recordFailure() {
        lock.lock()
        failed = true
        lock.unlock()
    }
}

/// Held by every copy of one ``LifetimeProbeSource/AsyncIterator``; its
/// `deinit` runs when the last copy is gone.
final class IteratorTracker: Sendable {
    let probe: LifetimeProbe

    init(_ probe: LifetimeProbe) {
        self.probe = probe
        probe.recordMade()
    }

    deinit {
        probe.recordReleased()
    }
}

/// The upstream a lifetime law hands the operator under test.
///
/// It yields the trial's elements, each after a virtual-time gap on the law's
/// clock, and then does what the law needs next: finish, fail, or park,
/// sleeping until it is cancelled. Every iterator it makes reports when its
/// last copy is released, which is what the release and cancellation laws read
/// once the consumer has gone. It has no public initializer;
/// ``checkAsyncLifetimePropertyLaws(for:using:applying:)`` makes one per trial.
///
/// After it finishes or fails it returns `nil`. A cancelled sleep ends it the
/// way a well-behaved source ends: while it waits to yield an element, the
/// sleep's `CancellationError` reaches the caller and every later call returns
/// `nil`; a parked source just returns `nil`.
public struct LifetimeProbeSource<Element: Sendable>: AsyncSequence, Sendable {
    /// How the source ends once its elements are spent.
    enum Ending: Sendable {
        case finish
        case fail
        /// Sleep on the law's clock until cancelled, then return `nil`.
        case park
    }

    /// An iterator over the source's elements.
    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        /// Longer than any lifetime law's horizon, so a parked source is woken
        /// by cancellation or not at all.
        static var parkDuration: Duration { .seconds(3_600) }

        let tracker: IteratorTracker
        let source: LifetimeProbeSource
        var position = 0
        var isDone = false

        public mutating func next() async throws -> Element? {
            guard !isDone else { return nil }
            if position < source.elements.count {
                do {
                    try await source.clock.sleep(for: source.gaps[position])
                } catch {
                    isDone = true
                    throw error
                }
                defer { position += 1 }
                return source.elements[position]
            }
            isDone = true
            switch source.ending {
            case .finish:
                try await source.clock.sleep(for: source.tailGap)
                return nil

            case .fail:
                try await source.clock.sleep(for: source.tailGap)
                source.probe.recordFailure()
                throw LifetimeProbeFailure()

            case .park:
                try? await source.clock.sleep(for: Self.parkDuration)
                return nil
            }
        }
    }

    let clock: VirtualClock
    let gaps: [Duration]
    let elements: [Element]
    let ending: Ending
    /// How long a finishing or failing source waits after its last element,
    /// so the ending can arrive while the consumer is not in `next()`.
    let tailGap: Duration
    let probe: LifetimeProbe

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(tracker: IteratorTracker(probe), source: self)
    }
}
