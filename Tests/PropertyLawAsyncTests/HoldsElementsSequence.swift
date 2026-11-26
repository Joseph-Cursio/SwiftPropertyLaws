import Foundation
import PropertyLawAsync

/// Faulty, and shaped like `debounce`: it keeps reading its base in a task of
/// its own and hands each element on only after `hold`, each from a task of its
/// own. A base failure that arrives while nobody waits becomes a plain finish
/// (`apple/swift-async-algorithms` issue 451's shape). With a holding operator,
/// the failure arrives after the consumer's first element only because the
/// failure law's source waits out a tail gap first.
struct HoldsElementsSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element: Sendable {
    typealias Element = Base.Element

    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [Result<Element?, Error>] = []
        private var waiter: CheckedContinuation<Result<Element?, Error>, Never>?
        private var producer: Task<Void, Never>?
        private var started = false
        private var isFinished = false

        /// Take the next result, or park until one is delivered. Returns
        /// whether the caller should start the producer.
        func take(_ continuation: CheckedContinuation<Result<Element?, Error>, Never>) -> Bool {
            lock.lock()
            if isFinished, queue.isEmpty {
                lock.unlock()
                continuation.resume(returning: .success(nil))
                return false
            }
            if !queue.isEmpty {
                let result = queue.removeFirst()
                if Self.isEnd(result) { isFinished = true }
                lock.unlock()
                continuation.resume(returning: result)
                return false
            }
            waiter = continuation
            let shouldStart = !started
            started = true
            lock.unlock()
            return shouldStart
        }

        static func isEnd(_ result: Result<Element?, Error>) -> Bool {
            if case .success(.some) = result { return false }
            return true
        }

        func setProducer(_ task: Task<Void, Never>) {
            lock.lock()
            producer = task
            lock.unlock()
        }

        /// Hand a result to the waiter, or queue it. A failure with nobody
        /// waiting is queued as a plain finish: the fault.
        func deliver(_ result: Result<Element?, Error>) {
            lock.lock()
            if let waiting = waiter {
                waiter = nil
                lock.unlock()
                waiting.resume(returning: result)
                return
            }
            if case .failure = result {
                queue.append(.success(nil))
            } else {
                queue.append(result)
            }
            lock.unlock()
        }

        func markFinished() {
            lock.lock()
            isFinished = true
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            let waiting = waiter
            waiter = nil
            isFinished = true
            let task = producer
            lock.unlock()
            task?.cancel()
            waiting?.resume(returning: .success(nil))
        }

        func stopProducer() {
            lock.lock()
            let task = producer
            lock.unlock()
            task?.cancel()
        }
    }

    final class Handle: Sendable {
        let state = State()

        deinit {
            state.stopProducer()
        }
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        let handle: Handle
        let base: Base
        let clock: LawClock
        let hold: Duration

        mutating func next() async throws -> Element? {
            let state = handle.state
            let upstream = base
            let lawClock = clock
            let delay = hold
            let result: Result<Element?, Error> = await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard state.take(continuation) else { return }
                    state.setProducer(Task {
                        do {
                            for try await element in upstream {
                                Task {
                                    try? await lawClock.sleep(for: delay)
                                    state.deliver(.success(element))
                                }
                            }
                            try? await lawClock.sleep(for: delay)
                            state.deliver(.success(nil))
                        } catch {
                            state.deliver(.failure(error))
                        }
                    })
                }
            } onCancel: {
                state.cancel()
            }
            if State.isEnd(result) { state.markFinished() }
            return try result.get()
        }
    }

    let base: Base
    let clock: LawClock
    let hold: Duration

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(handle: Handle(), base: base, clock: clock, hold: hold)
    }
}
