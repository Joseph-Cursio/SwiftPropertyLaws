/// Detail record for a `count` mismatch — `nil` when the law holds. Returned
/// from a single helper so the property closure, the formatter, and the
/// near-miss recorder all see a consistent view.
struct CountMismatchDetail {
    let reportedCount: Int
    let iteratedCount: Int

    var isOffByOne: Bool {
        Swift.abs(reportedCount - iteratedCount) == 1
    }

    var message: String {
        "collection reported count = \(reportedCount) "
            + "but iteration yielded \(iteratedCount) elements"
    }
}
