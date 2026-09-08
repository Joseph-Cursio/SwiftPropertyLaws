/// Three cases drawn from one space, as a named type rather than a 3-tuple.
///
/// The kit's ternary laws (`Semigroup.combineAssociativity` and the rest of the
/// algebraic cluster) are quantified over three values of one carrier, and that
/// is what ``Every/triples(of:)`` enumerates.
public struct Triple<Value: Sendable>: Sendable {
    public let first: Value
    public let second: Value
    public let third: Value

    public init(first: Value, second: Value, third: Value) {
        self.first = first
        self.second = second
        self.third = third
    }
}

extension Every {

    /// Every pairing of two spaces, ordered by **summed size**.
    ///
    /// ## Why summed size, and not either obvious alternative
    ///
    /// Row-major ordering (walk the second space inside the first) is
    /// lexicographically minimal and costs nothing to compute; ordering by the
    /// sum of the two *indices* is a closer proxy for "small". Both were
    /// measured against a failure region deliberately asymmetric across the
    /// factors, and they disagreed about which failure to report — row-major
    /// named a case that was minimal in the first factor and maximal in the
    /// second.
    ///
    /// Neither is what a reader means. "Smallest" means the smallest *case*, and
    /// index-sum only approximates that — worse, the less uniform the factors'
    /// size distributions are. Summed size is the thing itself.
    ///
    /// It is affordable because the precompute convolves the factors' **size
    /// histograms**, not their case counts: a space with `b` buckets and one
    /// with `c` buckets need `b × c` rectangles regardless of how many cases
    /// they hold. `subsets(of: 20)` has 21 buckets and a million cases.
    public static func product<First: Sendable, Second: Sendable>(
        _ first: Enumeration<First>,
        _ second: Enumeration<Second>
    ) -> Enumeration<(First, Second)> {
        guard !first.buckets.isEmpty, !second.buckets.isEmpty else {
            return Enumeration(
                buckets: [],
                fullCount: 0,
                build: { _ in preconditionFailure("Every.product: empty space") },
                describe: { _ in preconditionFailure("Every.product: empty space") }
            )
        }
        let rectangles = productRectangles(first.buckets, second.buckets)
        var buckets: [EnumerationBucket] = []
        for rectangle in rectangles {
            if let last = buckets.last, last.size == rectangle.size {
                buckets[buckets.count - 1] = EnumerationBucket(
                    size: last.size,
                    start: last.start,
                    count: last.count + rectangle.cellCount
                )
            } else {
                buckets.append(
                    EnumerationBucket(size: rectangle.size, start: rectangle.offset, count: rectangle.cellCount)
                )
            }
        }
        let scaledFull = first.fullCount.multipliedReportingOverflow(by: second.fullCount)
        precondition(!scaledFull.overflow, "Every.product: the product space does not fit in an Int")
        let locate: @Sendable (Int) -> (Int, Int) = { index in
            let rectangle = rectangle(holding: index, in: rectangles)
            let local = index - rectangle.offset
            return (
                rectangle.firstStart + local / rectangle.secondCount,
                rectangle.secondStart + local % rectangle.secondCount
            )
        }
        return Enumeration(
            buckets: buckets,
            fullCount: scaledFull.partialValue,
            build: { index in
                let (left, right) = locate(index)
                return (first[left], second[right])
            },
            describe: { index in
                let (left, right) = locate(index)
                return "\(first.address(of: left)) / \(second.address(of: right))"
            }
        )
    }

    /// Every ordered triple of one space's cases, by summed size — the shape the
    /// kit's algebraic laws are quantified over. An 8-case carrier yields 512
    /// triples, which is a walk rather than a sample.
    public static func triples<Value: Sendable>(
        of space: Enumeration<Value>
    ) -> Enumeration<Triple<Value>> {
        product(product(space, space), space).map { nested in
            Triple(first: nested.0.0, second: nested.0.1, third: nested.1)
        }
    }
}

/// A `(bucket × bucket)` pairing before it has been given a place. Named rather
/// than a 3-tuple so the sort key is written once and cannot drift between the
/// comparison and the layout that follows it.
struct PendingRectangle: Comparable {
    let size: Int
    let firstIndex: Int
    let secondIndex: Int

    /// Summed size first — that is the ordering. Ties fall back to the factors'
    /// own bucket order, which makes the layout deterministic.
    static func < (lhs: PendingRectangle, rhs: PendingRectangle) -> Bool {
        if lhs.size != rhs.size { return lhs.size < rhs.size }
        if lhs.firstIndex != rhs.firstIndex { return lhs.firstIndex < rhs.firstIndex }
        return lhs.secondIndex < rhs.secondIndex
    }
}

/// One `(bucket × bucket)` rectangle of a product space, placed at `offset` in
/// the summed-size order.
struct ProductRectangle: Sendable {
    let size: Int
    let offset: Int
    let cellCount: Int
    let firstStart: Int
    let firstCount: Int
    let secondStart: Int
    let secondCount: Int
}

/// Lay the `b × c` bucket rectangles out in summed-size order, ties broken by
/// the factors' own bucket order so the layout is deterministic.
func productRectangles(
    _ first: [EnumerationBucket],
    _ second: [EnumerationBucket]
) -> [ProductRectangle] {
    var pending: [PendingRectangle] = []
    pending.reserveCapacity(first.count * second.count)
    for (firstIndex, left) in first.enumerated() {
        for (secondIndex, right) in second.enumerated() {
            pending.append(
                PendingRectangle(size: left.size + right.size, firstIndex: firstIndex, secondIndex: secondIndex)
            )
        }
    }
    pending.sort()
    var laid: [ProductRectangle] = []
    laid.reserveCapacity(pending.count)
    var offset = 0
    for entry in pending {
        let left = first[entry.firstIndex]
        let right = second[entry.secondIndex]
        let cells = left.count.multipliedReportingOverflow(by: right.count)
        precondition(!cells.overflow, "Every.product: a bucket rectangle does not fit in an Int")
        let advanced = offset.addingReportingOverflow(cells.partialValue)
        precondition(!advanced.overflow, "Every.product: the product space does not fit in an Int")
        laid.append(
            ProductRectangle(
                size: entry.size,
                offset: offset,
                cellCount: cells.partialValue,
                firstStart: left.start,
                firstCount: left.count,
                secondStart: right.start,
                secondCount: right.count
            )
        )
        offset = advanced.partialValue
    }
    return laid
}

/// Binary search the rectangle holding `index`; offsets ascend by construction.
func rectangle(holding index: Int, in rectangles: [ProductRectangle]) -> ProductRectangle {
    var low = 0
    var high = rectangles.count - 1
    while low < high {
        let middle = (low + high + 1) / 2
        if rectangles[middle].offset <= index { low = middle } else { high = middle - 1 }
    }
    return rectangles[low]
}
