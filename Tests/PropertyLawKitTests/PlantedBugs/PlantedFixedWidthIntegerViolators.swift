import PropertyBased

// FixedWidthInteger has ~30 requirements on top of BinaryInteger; one
// violator's full conformance is verbose by necessity. We ship one clear
// plant (BrokenByteSwapped) to prove the framework detects custom-
// conformer bugs at this layer; the other FixedWidthInteger laws are
// self-validating against stdlib types in FixedWidthIntegerLawsTests.

/// Violates `FixedWidthInteger.byteSwappedInvolution`. `byteSwapped`
/// returns `value &+ 1` instead of the byte-reversed value, so
/// `x.byteSwapped.byteSwapped == x &+ 2 ≠ x` for any `x ≠ .max - 1` and
/// `≠ .max`. All other FixedWidthInteger laws still hold because every
/// other requirement forwards straight to the wrapped `Int32`.
struct BrokenByteSwapped: FixedWidthInteger, SignedInteger, Sendable, CustomStringConvertible {
    typealias IntegerLiteralType = Int32
    typealias Words = Int32.Words
    typealias Magnitude = UInt32

    var value: Int32

    init(value: Int32) { self.value = value }
    init(integerLiteral value: Int32) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int32(exactly: source) else { return nil }
        self.value = candidate
    }
    init<T: BinaryInteger>(_ source: T) { self.value = Int32(source) }
    init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.value = Int32(truncatingIfNeeded: source)
    }
    init<T: BinaryInteger>(clamping source: T) { self.value = Int32(clamping: source) }
    init<T: BinaryFloatingPoint>(_ source: T) { self.value = Int32(source) }
    init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let candidate = Int32(exactly: source) else { return nil }
        self.value = candidate
    }
    init(_truncatingBits source: UInt) {
        self.value = Int32(_truncatingBits: source)
    }

    static let isSigned = true
    static let bitWidth = Int32.bitWidth
    static let min = BrokenByteSwapped(value: Int32.min)
    static let max = BrokenByteSwapped(value: Int32.max)
    var bitWidth: Int { value.bitWidth }
    var trailingZeroBitCount: Int { value.trailingZeroBitCount }
    var leadingZeroBitCount: Int { value.leadingZeroBitCount }
    var nonzeroBitCount: Int { value.nonzeroBitCount }
    var words: Int32.Words { value.words }
    var magnitude: UInt32 { value.magnitude }
    var description: String { "BBS(\(value))" }

    /// The plant — `byteSwapped` adds 1 instead of reversing bytes.
    var byteSwapped: BrokenByteSwapped { BrokenByteSwapped(value: value &+ 1) }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { Int(other.value - value) }
    func advanced(by step: Int) -> Self { Self(value: value &+ Int32(step)) }
    func signum() -> Self { Self(value: value.signum()) }

    func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
        let pair = value.quotientAndRemainder(dividingBy: rhs.value)
        return (Self(value: pair.quotient), Self(value: pair.remainder))
    }

    func addingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.addingReportingOverflow(rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func subtractingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.subtractingReportingOverflow(rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func multipliedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.multipliedReportingOverflow(by: rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func dividedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.dividedReportingOverflow(by: rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func remainderReportingOverflow(dividingBy rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.remainderReportingOverflow(dividingBy: rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func multipliedFullWidth(by rhs: Self) -> (high: Self, low: UInt32) {
        let pair = value.multipliedFullWidth(by: rhs.value)
        return (Self(value: pair.high), pair.low)
    }
    func dividingFullWidth(_ dividend: (high: Self, low: UInt32)) -> (quotient: Self, remainder: Self) {
        let pair = value.dividingFullWidth((high: dividend.high.value, low: dividend.low))
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
    static func &+ (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value &+ rhs.value) }
    static func &- (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value &- rhs.value) }
    static func &* (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value &* rhs.value) }
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

extension Gen where Value == BrokenByteSwapped {
    static func brokenByteSwapped() -> Generator<BrokenByteSwapped, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { BrokenByteSwapped(value: Int32($0)) }
    }
}

/// Violates the eight FixedWidthInteger Strict laws whose counterexample
/// formatting `BrokenByteSwapped` does not exercise: `bitWidthMatchesType`,
/// the three arithmetic `reportingOverflow` consistency laws (now
/// strengthened past their original tautology), `wrappingArithmeticDoesNotTrap`
/// (likewise strengthened to pin the wrap-around boundary),
/// `dividedReportingOverflowOnDivByZero`, `minMaxBoundsAreReachable`, and
/// `nonzeroBitCountRange`. `byteSwapped` is left correct (covered already).
/// The off-by-one `reportingOverflow` plants below also skew the masking
/// operators (which are defined via those methods), tripping the wrapping law.
struct ChaoticFixedWidth: FixedWidthInteger, SignedInteger, Sendable, CustomStringConvertible {
    typealias IntegerLiteralType = Int32
    typealias Words = Int32.Words
    typealias Magnitude = UInt32

    var value: Int32

    init(value: Int32) { self.value = value }
    init(integerLiteral value: Int32) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int32(exactly: source) else { return nil }
        self.value = candidate
    }
    init<T: BinaryInteger>(_ source: T) { self.value = Int32(source) }
    init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.value = Int32(truncatingIfNeeded: source)
    }
    init<T: BinaryInteger>(clamping source: T) { self.value = Int32(clamping: source) }
    init<T: BinaryFloatingPoint>(_ source: T) { self.value = Int32(source) }
    init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard let candidate = Int32(exactly: source) else { return nil }
        self.value = candidate
    }
    init(_truncatingBits source: UInt) {
        self.value = Int32(_truncatingBits: source)
    }

    static let isSigned = true
    static let bitWidth = Int32.bitWidth
    /// Plant: a tiny reachable window so most sampled values fall outside it.
    static let min = ChaoticFixedWidth(value: 1)
    static let max = ChaoticFixedWidth(value: 2)
    /// Plant: instance bit width disagrees with `Self.bitWidth`.
    var bitWidth: Int { 999 }
    var trailingZeroBitCount: Int { value.trailingZeroBitCount }
    var leadingZeroBitCount: Int { value.leadingZeroBitCount }
    /// Plant: out of the `0...bitWidth` range mandated by the law.
    var nonzeroBitCount: Int { -1 }
    var words: Int32.Words { value.words }
    var magnitude: UInt32 { value.magnitude }
    var description: String { "ChaosFW(\(value))" }

    var byteSwapped: ChaoticFixedWidth { ChaoticFixedWidth(value: value.byteSwapped) }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { Int(other.value - value) }
    func advanced(by step: Int) -> Self { Self(value: value &+ Int32(step)) }
    func signum() -> Self { Self(value: value.signum()) }

    func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
        let pair = value.quotientAndRemainder(dividingBy: rhs.value)
        return (Self(value: pair.quotient), Self(value: pair.remainder))
    }

    // Plant: each partial value is off by one. Because the masking operators
    // are defined via these methods, this also skews `&+` / `&-` / `&*`,
    // which is what the strengthened consistency and wrapping laws detect.
    func addingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.addingReportingOverflow(rhs.value)
        return (Self(value: pair.partialValue &+ 1), pair.overflow)
    }
    func subtractingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.subtractingReportingOverflow(rhs.value)
        return (Self(value: pair.partialValue &+ 1), pair.overflow)
    }
    func multipliedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.multipliedReportingOverflow(by: rhs.value)
        return (Self(value: pair.partialValue &+ 1), pair.overflow)
    }
    /// Plant: divide-by-zero must report overflow; this never does.
    func dividedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool) {
        guard rhs.value != 0 else { return (self, false) }
        let pair = value.dividedReportingOverflow(by: rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func remainderReportingOverflow(dividingBy rhs: Self) -> (partialValue: Self, overflow: Bool) {
        guard rhs.value != 0 else { return (self, false) }
        let pair = value.remainderReportingOverflow(dividingBy: rhs.value)
        return (Self(value: pair.partialValue), pair.overflow)
    }
    func multipliedFullWidth(by rhs: Self) -> (high: Self, low: UInt32) {
        let pair = value.multipliedFullWidth(by: rhs.value)
        return (Self(value: pair.high), pair.low)
    }
    func dividingFullWidth(_ dividend: (high: Self, low: UInt32)) -> (quotient: Self, remainder: Self) {
        let pair = value.dividingFullWidth((high: dividend.high.value, low: dividend.low))
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
    static func &+ (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value &+ rhs.value) }
    static func &- (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value &- rhs.value) }
    static func &* (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value &* rhs.value) }
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

extension Gen where Value == ChaoticFixedWidth {
    static func chaoticFixedWidth() -> Generator<ChaoticFixedWidth, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { ChaoticFixedWidth(value: Int32($0)) }
    }
}
