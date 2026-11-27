import Foundation

/// A cut-down `share()` with swift-async-algorithms issue 473's "case 12"
/// race planted, and its fixed twin.
///
/// A producer task reads the base only when the consumer asks, hands the
/// element over, checks whether it has been told to stop, yields, and parks
/// until the next demand. Dropping the iterator while the sequence lives does
/// nothing, as a side unregistering from a live `share()` does; dropping the
/// sequence after the iterator tells the producer to stop, waking it only if
/// it is already parked. A producer that has checked and not yet parked then
/// parks for good, holding the base iterator. The fixed twin checks again
/// as it parks.
///
/// The window is opened by explicit `Task.yield()`s, not by where the
/// compiler happens to split code into jobs, and the consumer yields twice
/// after being handed an element, so under FIFO the producer always parks
/// first and the planted version passes. Only a seeded order that runs the
/// consumer's yields before the producer's can leak. Nothing here iterates a
/// `Dictionary` or `Set`, so a seed replays without deterministic hashing.
struct RacingShareSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable {
    typealias Element = Base.Element

    private let extent: Extent

    init(base: Base, fixed: Bool) {
        extent = Extent(State(base: base, fixed: fixed))
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(side: Side(extent.state))
    }

    struct Iterator: AsyncIteratorProtocol {
        let side: Side

        mutating func next() async throws -> Element? {
            try await side.state.next()
        }
    }

    /// Owned by the sequence and its copies; gone when the last one is.
    final class Extent: Sendable {
        let state: State

        init(_ state: State) {
            self.state = state
        }

        deinit {
            state.sequenceDropped()
        }
    }

    /// Owned by the iterator; gone when it is.
    final class Side: Sendable {
        let state: State

        init(_ state: State) {
            self.state = state
        }

        deinit {
            state.iteratorDropped()
        }
    }

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private let base: Base
        private let fixed: Bool
        private var started = false
        private var finished = false
        private var stopRequested = false
        private var sequenceAlive = true
        private var iteratorAlive = true
        private var pendingDemand = false
        private var demand: CheckedContinuation<Bool, Never>?
        private var consumer: CheckedContinuation<Element?, Error>?
        private var producer: Task<Void, Never>?

        init(base: Base, fixed: Bool) {
            self.base = base
            self.fixed = fixed
        }

        func next() async throws -> Element? {
            if Task.isCancelled {
                stop(cancellingTheProducer: true)
                return nil
            }
            let value = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (waiting: CheckedContinuation<Element?, Error>) in
                    ask(waiting)
                }
            } onCancel: {
                stop(cancellingTheProducer: true)
            }
            // The consumer's way back is longer than the producer's way to
            // its park, so FIFO always parks the producer first.
            await Task.yield()
            await Task.yield()
            return value
        }

        private func ask(_ waiting: CheckedContinuation<Element?, Error>) {
            lock.lock()
            if finished {
                lock.unlock()
                waiting.resume(returning: nil)
                return
            }
            consumer = waiting
            if !started {
                started = true
                producer = Task { await self.produce() }
                lock.unlock()
            } else if let parked = demand {
                demand = nil
                lock.unlock()
                parked.resume(returning: true)
            } else {
                pendingDemand = true
                lock.unlock()
            }
        }

        private func produce() async {
            var iterator = base.makeAsyncIterator()
            while true {
                let result: Result<Element?, Error>
                do {
                    result = .success(try await iterator.next())
                } catch {
                    result = .failure(error)
                }
                // The check: told to stop already? Past it, a stop that wakes
                // only a parked producer is missed until the producer parks.
                guard handOver(result) else { return }
                await Task.yield()
                guard await parkForDemand() else { return }
            }
        }

        /// Give the consumer `result`; `false` when the producer should end:
        /// the base ended or failed, or a stop was requested.
        private func handOver(_ result: Result<Element?, Error>) -> Bool {
            lock.lock()
            let waiting = consumer
            consumer = nil
            var goOn = !stopRequested
            if case .success(nil) = result {
                finished = true
                goOn = false
            } else if case .failure = result {
                finished = true
                goOn = false
            }
            lock.unlock()
            waiting?.resume(with: result)
            return goOn
        }

        /// Wait for the consumer's next demand; `false` means stop.
        private func parkForDemand() async -> Bool {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (parking: CheckedContinuation<Bool, Never>) in
                    lock.lock()
                    if pendingDemand {
                        pendingDemand = false
                        lock.unlock()
                        parking.resume(returning: true)
                    } else if Task.isCancelled || (fixed && stopRequested) {
                        lock.unlock()
                        parking.resume(returning: false)
                    } else {
                        demand = parking
                        lock.unlock()
                    }
                }
            } onCancel: {
                lock.lock()
                let parked = demand
                demand = nil
                lock.unlock()
                parked?.resume(returning: false)
            }
        }

        func iteratorDropped() {
            lock.lock()
            iteratorAlive = false
            let last = !sequenceAlive
            lock.unlock()
            if last {
                stop(cancellingTheProducer: true)
            }
        }

        /// The planted path: tells the producer to stop, and wakes it only if
        /// it is parked already.
        func sequenceDropped() {
            lock.lock()
            sequenceAlive = false
            let last = !iteratorAlive
            lock.unlock()
            if last {
                stop(cancellingTheProducer: false)
            }
        }

        private func stop(cancellingTheProducer: Bool) {
            lock.lock()
            stopRequested = true
            finished = true
            let parked = demand
            demand = nil
            let waiting = consumer
            consumer = nil
            let task = producer
            lock.unlock()
            parked?.resume(returning: false)
            waiting?.resume(returning: nil)
            if cancellingTheProducer {
                task?.cancel()
            }
        }
    }
}
