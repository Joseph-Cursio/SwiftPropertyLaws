import Foundation

/// An index that is *only* an index.
///
/// `Array`'s index is `Int`, so a generic algorithm written against `Collection` can accidentally
/// do arithmetic on it, compare indices from two different collections, or assume
/// `index(after:)` is addition — and pass its tests, because `Array` tolerates all of that. None
/// of it is guaranteed by `Collection`.
///
/// `MinimalIndex` exposes no arithmetic and carries the identity of the collection that vended
/// it. Comparing indices from two different instances traps rather than answering, which is the
/// behaviour a law suite wants: the alternative is a quiet wrong answer that looks like a
/// passing test.
///
/// Adapted in spirit from `swift-collections`' `_CollectionsTestSupport`, which takes the idea
/// from the standard library's own `StdlibUnittest`.
public struct MinimalIndex: Comparable, Hashable, Sendable {

    /// Identifies the collection instance that vended this index.
    internal let owner: Int
    internal let offset: Int

    internal init(owner: Int, offset: Int) {
        self.owner = owner
        self.offset = offset
    }

    private static func requireSameOwner(
        _ lhs: MinimalIndex,
        _ rhs: MinimalIndex,
        _ operation: StaticString
    ) {
        precondition(
            lhs.owner == rhs.owner,
            """
            MinimalIndex: \(operation) between indices from different collections. \
            Collection does not define this, and an algorithm that relies on it is relying on \
            Array's index being an Int.
            """
        )
    }

    public static func == (lhs: MinimalIndex, rhs: MinimalIndex) -> Bool {
        requireSameOwner(lhs, rhs, "==")
        return lhs.offset == rhs.offset
    }

    public static func < (lhs: MinimalIndex, rhs: MinimalIndex) -> Bool {
        requireSameOwner(lhs, rhs, "<")
        return lhs.offset < rhs.offset
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(owner)
        hasher.combine(offset)
    }
}

/// Hands out the instance identifiers `MinimalIndex` uses for provenance.
///
/// A lock rather than an `Atomic` because this target's deployment floor predates
/// `Synchronization`, and the cost is irrelevant: one increment per collection constructed.
final class MinimalInstanceCounter: @unchecked Sendable {
    private static let shared = MinimalInstanceCounter()
    private let lock = NSLock()
    private var next = 0

    static func allocate() -> Int {
        shared.lock.withLock {
            shared.next += 1
            return shared.next
        }
    }
}
