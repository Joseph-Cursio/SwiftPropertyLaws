import PropertyBased

/// Violates `BinaryInteger.bitwiseDoubleNegation`. `~` flips bits then sets
/// the lowest bit to 1, so `~~x` recovers everything except the LSB and
/// `~~x ≠ x` for any `x` whose LSB is 0. All other bitwise / arithmetic /
/// division laws still hold because every other requirement forwards
/// straight to `Int`.
struct BrokenBitwiseNegation: BinaryInteger, Sendable, CustomStringConvertible {
    typealias IntegerLiteralType = Int
    typealias Words = Int.Words
    typealias Magnitude = UInt

    var value: Int

    init(value: Int) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }
    init<T: BinaryInteger>(_ source: T) { self.value = Int(source) }
    init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.value = Int(truncatingIfNeeded: source)
    }
    init<T: BinaryInteger>(clamping source: T) { self.value = Int(clamping: source) }
    init<T: BinaryFloatingPoint>(_ source: T) { self.value = Int(source) }
    init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }

    static let isSigned = true
    var bitWidth: Int { value.bitWidth }
    var trailingZeroBitCount: Int { value.trailingZeroBitCount }
    var words: Int.Words { value.words }
    var magnitude: UInt { value.magnitude }
    var description: String { "BBN(\(value))" }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { other.value - value }
    func advanced(by step: Int) -> Self { Self(value: value + step) }

    func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
        let pair = value.quotientAndRemainder(dividingBy: rhs.value)
        return (Self(value: pair.quotient), Self(value: pair.remainder))
    }

    static func + (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value + rhs.value) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value - rhs.value) }
    static func * (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value * rhs.value) }
    static func / (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value / rhs.value) }
    static func % (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value % rhs.value) }
    static func & (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value & rhs.value) }
    static func | (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value | rhs.value) }
    static func ^ (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value ^ rhs.value) }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    static func /= (lhs: inout Self, rhs: Self) { lhs = lhs / rhs }
    static func %= (lhs: inout Self, rhs: Self) { lhs = lhs % rhs }
    static func &= (lhs: inout Self, rhs: Self) { lhs = lhs & rhs }
    static func |= (lhs: inout Self, rhs: Self) { lhs = lhs | rhs }
    static func ^= (lhs: inout Self, rhs: Self) { lhs = lhs ^ rhs }

    static func << <O: BinaryInteger>(lhs: Self, rhs: O) -> Self {
        Self(value: lhs.value << rhs)
    }
    static func >> <O: BinaryInteger>(lhs: Self, rhs: O) -> Self {
        Self(value: lhs.value >> rhs)
    }
    static func <<= <O: BinaryInteger>(lhs: inout Self, rhs: O) { lhs = lhs << rhs }
    static func >>= <O: BinaryInteger>(lhs: inout Self, rhs: O) { lhs = lhs >> rhs }

    /// The plant: `~` should flip every bit. We force the LSB to 1 after the
    /// flip, so `~~x` recovers everything except the LSB. For any even `x`
    /// (LSB = 0), `~~x = x | 1 ≠ x`.
    static prefix func ~ (operand: Self) -> Self {
        Self(value: ~operand.value | 1)
    }
}

extension Gen where Value == BrokenBitwiseNegation {
    static func brokenBitwiseNegation() -> Generator<BrokenBitwiseNegation, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { BrokenBitwiseNegation(value: $0) }
    }
}

/// Violates *every* BinaryInteger Strict law except `bitwiseDoubleNegation`
/// (which `BrokenBitwiseNegation` already covers) in a single conformer, so
/// the per-law counterexample-formatting paths all execute in one run.
///
/// Each operator is broken independently so the corresponding law fails on
/// its own terms — division/remainder, every bitwise operator, shift, and
/// `trailingZeroBitCount` — while `~` is left correct so double-negation
/// keeps passing. `quotientAndRemainder` forwards to `Int`'s correct
/// implementation so the consistency law sees the broken `/` and `%`
/// disagree with the honest pair.
struct ChaoticInteger: BinaryInteger, Sendable, CustomStringConvertible {
    typealias IntegerLiteralType = Int
    typealias Words = Int.Words
    typealias Magnitude = UInt

    var value: Int

    init(value: Int) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }
    init<T: BinaryInteger>(_ source: T) { self.value = Int(source) }
    init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.value = Int(truncatingIfNeeded: source)
    }
    init<T: BinaryInteger>(clamping source: T) { self.value = Int(clamping: source) }
    init<T: BinaryFloatingPoint>(_ source: T) { self.value = Int(source) }
    init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }

    static let isSigned = true
    var bitWidth: Int { value.bitWidth }
    /// Plant: out of the `0...bitWidth` range mandated by the law.
    var trailingZeroBitCount: Int { -1 }
    var words: Int.Words { value.words }
    var magnitude: UInt { value.magnitude }
    var description: String { "Chaos(\(value))" }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { other.value - value }
    func advanced(by step: Int) -> Self { Self(value: value + step) }

    /// Honest pair — so `quotientAndRemainderConsistency` catches the broken
    /// `/` and `%` below disagreeing with the correct quotient/remainder.
    func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
        let pair = value.quotientAndRemainder(dividingBy: rhs.value)
        return (Self(value: pair.quotient), Self(value: pair.remainder))
    }

    static func + (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value + rhs.value) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value - rhs.value) }
    static func * (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value * rhs.value) }
    /// Plant: off-by-one quotient breaks every division law.
    static func / (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value / rhs.value &+ 1) }
    /// Plant: remainder magnitude `2·|y|` always exceeds `|y|`.
    static func % (lhs: Self, rhs: Self) -> Self { Self(value: rhs.value &* 2) }
    /// Plant: non-idempotent and non-commutative (`+lhs` skews each side).
    static func & (lhs: Self, rhs: Self) -> Self { Self(value: (lhs.value & rhs.value) &+ lhs.value) }
    static func | (lhs: Self, rhs: Self) -> Self { Self(value: (lhs.value | rhs.value) &+ lhs.value) }
    /// Plant: `x ^ x ≠ 0` and `x ^ 0 ≠ x`.
    static func ^ (lhs: Self, rhs: Self) -> Self { Self(value: (lhs.value ^ rhs.value) &+ 1) }
    static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    static func /= (lhs: inout Self, rhs: Self) { lhs = lhs / rhs }
    static func %= (lhs: inout Self, rhs: Self) { lhs = lhs % rhs }
    static func &= (lhs: inout Self, rhs: Self) { lhs = lhs & rhs }
    static func |= (lhs: inout Self, rhs: Self) { lhs = lhs | rhs }
    static func ^= (lhs: inout Self, rhs: Self) { lhs = lhs ^ rhs }

    /// Plant: left shift is off by one, so `x << 0 ≠ x`.
    static func << <O: BinaryInteger>(lhs: Self, rhs: O) -> Self {
        Self(value: (lhs.value << rhs) &+ 1)
    }
    static func >> <O: BinaryInteger>(lhs: Self, rhs: O) -> Self {
        Self(value: lhs.value >> rhs)
    }
    static func <<= <O: BinaryInteger>(lhs: inout Self, rhs: O) { lhs = lhs << rhs }
    static func >>= <O: BinaryInteger>(lhs: inout Self, rhs: O) { lhs = lhs >> rhs }

    /// Left correct so `bitwiseDoubleNegation` still passes here.
    static prefix func ~ (operand: Self) -> Self { Self(value: ~operand.value) }
}

extension Gen where Value == ChaoticInteger {
    static func chaoticInteger() -> Generator<ChaoticInteger, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { ChaoticInteger(value: $0) }
    }
}
