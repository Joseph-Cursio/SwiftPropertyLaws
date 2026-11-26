import Foundation

/// How long a test waits in real time for something that normally takes
/// milliseconds: a task the runtime runs, a flag set from another thread, an
/// escape coming back.
///
/// Generous on purpose. Before Swift 6.4, `swift test` runs every test target
/// in one process, and on CI's 3-core macos-15 runner the other suites can
/// hold every cooperative-pool thread, and every thread the global Dispatch
/// queues would get, for seconds at a time (measured: about 12 s). A wait ends
/// the moment its condition holds, so this costs nothing when things work.
let patience = Duration.seconds(60)

/// Where the tests resume continuations and start outside work from. A
/// private serial queue gets a thread of its own even when the cooperative
/// pool and `DispatchQueue.global()` have none to give, so the Dispatch hop
/// itself is not held up by unrelated tests. It is still Dispatch, so a
/// continuation resumed here is resumed from outside the run. A `Task`
/// started from it still runs on the cooperative pool, so a test that relies
/// on one still needs `escapingVerdict` or ``patience``.
let outsideQueue = DispatchQueue(label: "PropertyLawAsyncTests.outside")

/// Inside a run's body, waiting for work elsewhere: let the run's queue
/// drain, then rest the run's thread for a moment, so the wait does not keep
/// a core busy on a runner that has few.
func yieldAndRest() async {
    await Task.yield()
    restThisThread()
}

/// Rest the calling thread for a moment, without giving it up to anything
/// else: for a run's body that must keep the run's thread busy.
func restThisThread() {
    Thread.sleep(forTimeInterval: 0.001)
}
