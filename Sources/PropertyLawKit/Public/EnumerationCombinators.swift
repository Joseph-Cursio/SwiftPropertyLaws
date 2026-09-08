/// The bounded spaces the kit's own laws are quantified over.
///
/// Deliberately **not** a port of `StdlibUnittest`'s four combinators, whose
/// subject is `Collection` index arithmetic. The subject here is 39 protocols,
/// and the spaces that pay are different ones — `triples` over a small
/// algebraic carrier has no ancestor upstream, and `permutations` is absent
/// because no law in this kit is quantified over an ordering.
///
/// Every constructor is **closed-form**: cases are computed from an index, never
/// materialised. That is not an optimisation, it is what makes composition
/// usable — the product of a 3.6-million-case space and a 65-thousand-case one
/// is 238 billion cases, which no machine will hold and any of them can index.
public enum Every {

    /// Every element of a collection, in the order given.
    ///
    /// `size` defaults to `0` for every case, which says *this space declares no
    /// size notion* — the honest default for an arbitrary carrier, where no
    /// element is smaller than another. The resulting single bucket preserves
    /// the caller's order exactly. Supply `size` where the elements do have a
    /// magnitude and you want products ordered by it.
    ///
    /// Materialises its argument, so it is meant for explicit case lists — a
    /// small algebraic carrier, an enum's `allCases`. Structured spaces below
    /// stay closed-form at any size.
    public static func elements<Source: Collection>(
        _ label: String,
        in source: Source,
        size: (@Sendable (Source.Element) -> Int)? = nil
    ) -> Enumeration<Source.Element> where Source.Element: Sendable {
        let items = Array(source)
        guard !items.isEmpty else {
            return Enumeration(
                buckets: [],
                build: { _ in preconditionFailure("Every.elements: empty space") },
                describe: { _ in preconditionFailure("Every.elements: empty space") }
            )
        }
        guard let size else {
            return Enumeration(
                buckets: [EnumerationBucket(size: 0, start: 0, count: items.count)],
                build: { items[$0] },
                describe: { "\(label)=\(items[$0])" }
            )
        }
        // A caller-supplied size need not ascend with position, so the space is
        // reordered to honour the invariant rather than the invariant being
        // relaxed to accept it. Ties keep their given order (`sort` on the
        // paired index is a stable order by construction).
        let ordered = items.indices
            .map { (position: $0, magnitude: size(items[$0])) }
            .sorted { ($0.magnitude, $0.position) < ($1.magnitude, $1.position) }
        let reordered = ordered.map { items[$0.position] }
        var buckets: [EnumerationBucket] = []
        for (index, entry) in ordered.enumerated() {
            if let last = buckets.last, last.size == entry.magnitude {
                buckets[buckets.count - 1] = .init(size: last.size, start: last.start, count: last.count + 1)
            } else {
                buckets.append(.init(size: entry.magnitude, start: index, count: 1))
            }
        }
        return Enumeration(
            buckets: buckets,
            build: { reordered[$0] },
            describe: { "\(label)=\(reordered[$0])" }
        )
    }

    /// Every subrange of `0 ..< bound`, shortest first, then by lower bound.
    /// Size is the range's length, so the first case is always empty.
    ///
    /// `(bound + 1)(bound + 2) / 2` cases, including the empty ranges at each
    /// position and the whole span.
    public static func ranges(_ label: String, upTo bound: Int) -> Enumeration<Range<Int>> {
        precondition(bound >= 0, "Every.ranges: negative bound \(bound)")
        var buckets: [EnumerationBucket] = []
        var start = 0
        for length in 0 ... bound {
            let inLength = bound - length + 1
            buckets.append(.init(size: length, start: start, count: inLength))
            start += inLength
        }
        let table = buckets
        // Closed-form unranking: the bucket gives the length, the offset within
        // it gives the lower bound.
        let decode: @Sendable (Int, [EnumerationBucket]) -> Range<Int> = { index, table in
            for bucket in table where index < bucket.start + bucket.count {
                let lower = index - bucket.start
                return lower ..< (lower + bucket.size)
            }
            preconditionFailure("Every.ranges: index \(index) outside the space")
        }
        return Enumeration(
            buckets: buckets,
            build: { decode($0, table) },
            describe: { "\(label)=\(decode($0, table).lowerBound)..<\(decode($0, table).upperBound)" }
        )
    }

    /// Every subset of `0 ..< bound`, smallest cardinality first, lexicographic
    /// within a cardinality. Size is the cardinality, so the first case is the
    /// empty set. `2^bound` cases.
    ///
    /// Unranked through the combinatorial number system rather than by filtering
    /// bitmasks, which keeps it closed-form: reaching case 900 000 of `2^20`
    /// costs the same as reaching case 3.
    public static func subsets(_ label: String, of bound: Int) -> Enumeration<[Int]> {
        precondition(bound >= 0, "Every.subsets: negative bound \(bound)")
        precondition(bound < 62, "Every.subsets: 2^\(bound) does not fit in an Int")
        var buckets: [EnumerationBucket] = []
        var start = 0
        for cardinality in 0 ... bound {
            let inCardinality = binomial(bound, cardinality)
            buckets.append(.init(size: cardinality, start: start, count: inCardinality))
            start += inCardinality
        }
        let table = buckets
        let decode: @Sendable (Int, [EnumerationBucket]) -> [Int] = { index, table in
            for bucket in table where index < bucket.start + bucket.count {
                var rest = index - bucket.start
                var remaining = bucket.size
                var candidate = 0
                var chosen: [Int] = []
                while remaining > 0 {
                    let skipped = binomial(bound - candidate - 1, remaining - 1)
                    if rest < skipped {
                        chosen.append(candidate)
                        remaining -= 1
                    } else {
                        rest -= skipped
                    }
                    candidate += 1
                }
                return chosen
            }
            preconditionFailure("Every.subsets: index \(index) outside the space")
        }
        return Enumeration(
            buckets: buckets,
            build: { decode($0, table) },
            describe: { "\(label)=\(decode($0, table))" }
        )
    }
}

/// `n` choose `k`, trapping on overflow rather than wrapping — a silently
/// wrapped bucket count would make the space misreport its own size.
@Sendable
func binomial(_ setSize: Int, _ pick: Int) -> Int {
    guard pick >= 0, pick <= setSize, setSize >= 0 else { return 0 }
    var result = 1
    for step in 0 ..< min(pick, setSize - pick) {
        let scaled = result.multipliedReportingOverflow(by: setSize - step)
        precondition(!scaled.overflow, "binomial(\(setSize), \(pick)) overflows Int")
        result = scaled.partialValue / (step + 1)
    }
    return result
}
