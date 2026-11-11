import PropertyBased

/// Violates `SignedInteger.signednessConsistency`. `signum()` always
/// returns 0, even for non-zero values. Inherited BinaryInteger /
/// SignedNumeric / Numeric / AdditiveArithmetic laws still hold.
struct LyingSignum: SignedInteger, Sendable, CustomStringConvertible {
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
    var description: String { "LSI(\(value))" }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { other.value - value }
    func advanced(by step: Int) -> Self { Self(value: value + step) }

    /// The plant: signum always returns 0, regardless of sign.
    func signum() -> Self { Self(value: 0) }

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

    static prefix func ~ (operand: Self) -> Self { Self(value: ~operand.value) }
    static prefix func - (operand: Self) -> Self { Self(value: -operand.value) }
    mutating func negate() { value.negate() }
}

extension Gen where Value == LyingSignum {
    static func lyingSignum() -> Generator<LyingSignum, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { LyingSignum(value: $0) }
    }
}
