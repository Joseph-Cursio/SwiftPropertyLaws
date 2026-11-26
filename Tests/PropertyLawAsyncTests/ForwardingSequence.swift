import Foundation
import PropertyLawAsync

/// A planted operator for the lifetime laws: it forwards its base through a
/// task of its own, the way `debounce` and `buffer` do, and each ``Defect``
/// reproduces one way such an operator goes wrong. With `.correct` it is a
/// correct operator, and every lifetime law must hold for it.
///
/// The producer task starts on the first `next()`. Elements and the base's
/// ending wait in a queue until the consumer asks for them.
struct ForwardingSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable {
    typealias Element = Base.Element

    /// One fault per lifetime law, each modelled on a real swift-async-algorithms bug.
    enum Defect: Sendable {
        case correct
        /// Dropping the iterator never stops the producer, which keeps the base
        /// iterator. `buffer`'s break-after-first leak (`apple/swift-async-algorithms` PR 352).
        case keepsUpstreamAfterDrop
        /// A `next()` that finds its task already cancelled finishes without
        /// cancelling the producer, and forgets it, so a later drop cannot stop
        /// it either. `debounce` cancelled between `next()` calls (`apple/swift-async-algorithms` issue 475).
        case forgetsUpstreamOnCancelledNext
        /// A base failure that arrives while nobody is waiting is turned into a
        /// plain finish. `debounce`'s lost failure without demand (`apple/swift-async-algorithms` issue 451).
        case dropsFailureWithoutDemand
        /// Like `forgetsUpstreamOnCancelledNext`, but only when elements are
        /// already queued, the state the consumer's pause outside `next()`
        /// lets the producer reach.
        case forgetsUpstreamOnCancelledNextWhenQueued
        /// A cancellation that arrives while the consumer waits in `next()`
        /// wakes it but forgets the producer instead of cancelling it.
        case forgetsUpstreamWhenCancelledWhileWaiting
        /// `next()` neither checks cancellation nor reacts to it, so a
        /// cancelled consumer waits for an element that never comes.
        case ignoresCancellationInNext
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let handle: Handle

        mutating func next() async throws -> Element? {
            try await handle.storage.next()
        }
    }

    /// Held by every copy of one iterator; the last copy's release is the drop.
    final class Handle: Sendable {
        let storage: Storage

        init(_ storage: Storage) {
            self.storage = storage
        }

        deinit {
            storage.iteratorDropped()
        }
    }

    final class Storage: @unchecked Sendable {
        private let lock = NSLock()
        private let base: Base
        private let defect: Defect
        private let delay: (clock: LawClock, duration: Duration)?
        private var producer: Task<Void, Never>?
        private var started = false
        private var queue: [Result<Element?, Error>] = []
        private var waiter: CheckedContinuation<Result<Element?, Error>, Never>?
        private var isFinished = false

        init(base: Base, defect: Defect, delay: (clock: LawClock, duration: Duration)?) {
            self.base = base
            self.defect = defect
            self.delay = delay
        }

        func next() async throws -> Element? {
            if Task.isCancelled, defect != .ignoresCancellationInNext {
                let forgets = defect == .forgetsUpstreamOnCancelledNext
                    || (defect == .forgetsUpstreamOnCancelledNextWhenQueued && hasQueued())
                finish(stoppingProducer: !forgets)
                return nil
            }
            let result: Result<Element?, Error>
            if defect == .ignoresCancellationInNext {
                result = await take()
            } else {
                result = await withTaskCancellationHandler {
                    await take()
                } onCancel: {
                    self.cancelWaiting()
                }
            }
            return try result.get()
        }

        private func hasQueued() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return !queue.isEmpty
        }

        func iteratorDropped() {
            guard defect != .keepsUpstreamAfterDrop else { return }
            lock.lock()
            let task = producer
            lock.unlock()
            task?.cancel()
        }

        private func take() async -> Result<Element?, Error> {
            await withCheckedContinuation { continuation in
                lock.lock()
                if isFinished, queue.isEmpty {
                    lock.unlock()
                    continuation.resume(returning: .success(nil))
                    return
                }
                if !queue.isEmpty {
                    let result = queue.removeFirst()
                    if case .success(nil) = result { isFinished = true }
                    if case .failure = result { isFinished = true }
                    lock.unlock()
                    continuation.resume(returning: result)
                    return
                }
                waiter = continuation
                let shouldStart = !started
                started = true
                lock.unlock()
                if shouldStart { startProducer() }
            }
        }

        private func startProducer() {
            let task = Task { [base, delay] in
                do {
                    for try await element in base {
                        if let delay {
                            try await delay.clock.sleep(for: delay.duration)
                        }
                        self.deliver(.success(element))
                    }
                    self.deliver(.success(nil))
                } catch {
                    self.deliver(.failure(error))
                }
            }
            lock.lock()
            producer = task
            lock.unlock()
        }

        private func deliver(_ result: Result<Element?, Error>) {
            lock.lock()
            if let waiter {
                self.waiter = nil
                if case .success(nil) = result { isFinished = true }
                if case .failure = result { isFinished = true }
                lock.unlock()
                waiter.resume(returning: result)
                return
            }
            if case .failure = result, defect == .dropsFailureWithoutDemand {
                queue.append(.success(nil))
            } else {
                queue.append(result)
            }
            lock.unlock()
        }

        private func cancelWaiting() {
            lock.lock()
            let waiting = waiter
            waiter = nil
            isFinished = true
            let task = producer
            let forgets = defect == .forgetsUpstreamWhenCancelledWhileWaiting
            if forgets { producer = nil }
            lock.unlock()
            if !forgets { task?.cancel() }
            waiting?.resume(returning: .success(nil))
        }

        private func finish(stoppingProducer: Bool) {
            lock.lock()
            isFinished = true
            queue.removeAll()
            let task = producer
            if !stoppingProducer { producer = nil }
            lock.unlock()
            if stoppingProducer { task?.cancel() }
        }
    }

    let base: Base
    let defect: Defect
    var delay: (clock: LawClock, duration: Duration)?

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(handle: Handle(Storage(base: base, defect: defect, delay: delay)))
    }
}
