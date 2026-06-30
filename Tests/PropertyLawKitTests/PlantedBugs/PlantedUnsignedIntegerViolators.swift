import PropertyBased

/// Violates `UnsignedInteger.magnitudeIsSelf`. `magnitude` returns
/// `UInt(value &+ 1)` instead of `UInt(value)`, so for any value `≠ UInt.max`,
/// `x.magnitude` lands at the next integer up. The protocol requires
/// `Magnitude == Self`, so we still report Self-typed magnitudes — the lie
/// is in the value, not the type. UnsignedInteger.nonNegative is preserved.
struct LyingMagnitude: UnsignedInteger, Sendable, CustomStringConvertible {
    typealias IntegerLiteralType = UInt
    typealias Words = UInt.Words
    typealias Magnitude = LyingMagnitude

    var value: UInt

    init(value: UInt) { self.value = value }
    init(integerLiteral value: UInt) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = UInt(exactly: source) else { return nil }
        self.value = candidate
    }
    init<T: BinaryInteger>(_ source: T) { self.value = UInt(source) }
    init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.value = UInt(truncatingIfNeeded: source)
    }
    init<T: BinaryInteger>(clamping source: T) { self.value = UInt(clamping: source) }
    init<T: BinaryFloatingPoint>(_ source: T) { self.value = UInt(source) }
    init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let candidate = UInt(exactly: source) else { return nil }
        self.value = candidate
    }

    static let isSigned = false
    var bitWidth: Int { value.bitWidth }
    var trailingZeroBitCount: Int { value.trailingZeroBitCount }
    var words: UInt.Words { value.words }
    var description: String { "LMG(\(value))" }

    /// The plant: magnitude reports value &+ 1 instead of value, so
    /// `x.magnitude == x` fails for every sample where `value &+ 1 != value`
    /// (i.e. every sample except `UInt.max`).
    var magnitude: LyingMagnitude { LyingMagnitude(value: value &+ 1) }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { Int(other.value) - Int(value) }
    func advanced(by step: Int) -> Self {
        Self(value: UInt(Int(value) + step))
    }

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
}

extension Gen where Value == LyingMagnitude {
    static func lyingMagnitude() -> Generator<LyingMagnitude, some SendableSequenceType> {
        Gen<Int>.int(in: 1...50).map { LyingMagnitude(value: UInt($0)) }
    }
}

/// Violates the strengthened `UnsignedInteger.nonNegative` (`x >= .zero`).
/// The law now compares through the type's own `Comparable` ordering, so this
/// conformer lies in `<`: every value reports itself as *less than* zero,
/// making `x >= .zero` (i.e. `!(x < .zero)`) false. `magnitude` and `==` stay
/// honest (they compare the stored `value`), so `magnitudeIsSelf` still passes.
struct NegativeClaimingUnsigned: UnsignedInteger, Sendable, CustomStringConvertible {
    typealias IntegerLiteralType = UInt
    typealias Words = UInt.Words
    typealias Magnitude = NegativeClaimingUnsigned

    var value: UInt

    init(value: UInt) { self.value = value }
    init(integerLiteral value: UInt) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = UInt(exactly: source) else { return nil }
        self.value = candidate
    }
    init<T: BinaryInteger>(_ source: T) { self.value = UInt(source) }
    init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.value = UInt(truncatingIfNeeded: source)
    }
    init<T: BinaryInteger>(clamping source: T) { self.value = UInt(clamping: source) }
    init<T: BinaryFloatingPoint>(_ source: T) { self.value = UInt(source) }
    init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let candidate = UInt(exactly: source) else { return nil }
        self.value = candidate
    }

    static let isSigned = false
    var bitWidth: Int { value.bitWidth }
    var trailingZeroBitCount: Int { value.trailingZeroBitCount }
    var words: UInt.Words { value.words }
    var magnitude: NegativeClaimingUnsigned { self }
    var description: String { "NCU(\(value))" }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    /// The plant: everything orders below zero, so `x >= .zero` is false while
    /// non-zero comparisons stay honest.
    static func < (lhs: Self, rhs: Self) -> Bool {
        if rhs.value == 0 { return true }
        return lhs.value < rhs.value
    }

    func distance(to other: Self) -> Int { Int(other.value) - Int(value) }
    func advanced(by step: Int) -> Self {
        Self(value: UInt(Int(value) + step))
    }

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
}

extension Gen where Value == NegativeClaimingUnsigned {
    static func negativeClaimingUnsigned()
        -> Generator<NegativeClaimingUnsigned, some SendableSequenceType> {
        Gen<Int>.int(in: 1...50).map { NegativeClaimingUnsigned(value: UInt($0)) }
    }
}
