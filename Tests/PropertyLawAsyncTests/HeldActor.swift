import Foundation

/// A default actor that a task outside a run can hold, blocking its thread,
/// so a task of the run that calls it waits in the actor's queue and is then
/// run on the holder's thread, never through the global enqueue hook.
actor HeldActor {
    /// Block this actor's thread, setting `holding` once the actor is held,
    /// until `reached` is set and `seconds` more of real time have passed.
    /// Waiting for `reached` rather than a fixed time keeps the actor held
    /// however late, under load, the caller gets to it.
    func hold(holding: Latch, until reached: Latch, thenFor seconds: TimeInterval) {
        holding.set()
        let giveUp = ContinuousClock.now.advanced(by: .seconds(5))
        while !reached.isSet, ContinuousClock.now < giveUp {
            Thread.sleep(forTimeInterval: 0.001)
        }
        Thread.sleep(forTimeInterval: seconds)
    }

    func touch() -> Int {
        1
    }
}
