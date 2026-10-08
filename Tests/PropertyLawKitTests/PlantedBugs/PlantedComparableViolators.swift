import PropertyBased

/// Violates Comparable.antisymmetry: `<` orders by `bucket` while `==`
/// distinguishes by `value`. Two values with the same bucket but different
/// values satisfy `x <= y && y <= x` (because both `<` checks return false)
/// without satisfying `x == y`. Probability per trial ≈ 0.5 × 0.9.
struct BucketedOrder: Comparable, Sendable, CustomStringConvertible {
    let bucket: Int
    let value: Int

    static func == (lhs: BucketedOrder, rhs: BucketedOrder) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: BucketedOrder, rhs: BucketedOrder) -> Bool {
        lhs.bucket < rhs.bucket
    }

    var description: String { "B\(bucket)(\(value))" }
}

extension Gen where Value == BucketedOrder {
    static func bucketedOrder() -> Generator<BucketedOrder, some SendableSequenceType> {
        zip(Gen<Int>.int(in: 0...1), Gen<Int>.int(in: 0...10))
            .map { bucket, value in BucketedOrder(bucket: bucket, value: value) }
    }
}

/// Violates Comparable.operatorConsistency: `<` always returns true, which
/// makes the derived `<=` (`!(rhs < lhs)`) always false. So `x < y && !(x <= y)`
/// holds for every pair — internally inconsistent operator surface even
/// though `<=` itself is the protocol's default.
struct AlwaysLessThan: Comparable, Sendable, CustomStringConvertible {
    let value: Int

    static func == (lhs: AlwaysLessThan, rhs: AlwaysLessThan) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: AlwaysLessThan, rhs: AlwaysLessThan) -> Bool {
        true
    }

    var description: String { "ALT(\(value))" }
}

extension Gen where Value == AlwaysLessThan {
    static func alwaysLessThan() -> Generator<AlwaysLessThan, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20).map { AlwaysLessThan(value: $0) }
    }
}

/// Violates Comparable.transitivity (of `<=`): a rock-paper-scissors cycle
/// over three buckets makes `a <= b && b <= c` true while `a <= c` is false.
struct CyclicOrder: Comparable, Sendable, CustomStringConvertible {
    let bucket: Int // 0, 1, or 2

    static func == (lhs: CyclicOrder, rhs: CyclicOrder) -> Bool {
        lhs.bucket == rhs.bucket
    }

    static func < (lhs: CyclicOrder, rhs: CyclicOrder) -> Bool {
        // 0 < 1, 1 < 2, 2 < 0 (cycle)
        let lhsBucket = lhs.bucket
        let rhsBucket = rhs.bucket
        return (lhsBucket == 0 && rhsBucket == 1)
            || (lhsBucket == 1 && rhsBucket == 2)
            || (lhsBucket == 2 && rhsBucket == 0)
    }

    var description: String { "C\(bucket)" }
}

extension Gen where Value == CyclicOrder {
    static func cyclicOrder() -> Generator<CyclicOrder, some SendableSequenceType> {
        Gen<Int>.int(in: 0...2).map { CyclicOrder(bucket: $0) }
    }
}

/// Violates Comparable.irreflexivity: `<` is written as `<=`, so `x < x` holds.
/// `==` is synthesized and correct.
///
/// Every other Comparable law is stated over two values and sees this bug only
/// when the two are equal — which, at the width the generator below draws from,
/// two independent draws essentially never are. So this is the violator that
/// shows the unary law is needed rather than redundant.
struct NonStrictLessThan: Comparable, Sendable, CustomStringConvertible {
    let cents: Int

    static func < (lhs: NonStrictLessThan, rhs: NonStrictLessThan) -> Bool {
        lhs.cents <= rhs.cents
    }

    var description: String { "NSL(\(cents))" }
}

extension Gen where Value == NonStrictLessThan {
    /// Deliberately wide, ±1 000 000 — a realistic money range, and wide enough
    /// that an equal pair turns up about once per thousand runs of 1 000 trials.
    static func nonStrictLessThan() -> Generator<NonStrictLessThan, some SendableSequenceType> {
        Gen<Int>.int(in: -1_000_000 ... 1_000_000).map { NonStrictLessThan(cents: $0) }
    }
}
