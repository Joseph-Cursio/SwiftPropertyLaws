import PropertyBased

/// One fault per integer type, where `ChaoticFixedWidth` plants every fault at
/// once.
///
/// The `reportingOverflow` consistency laws and the wrapping law each join
/// several independent checks with `&&`. A type that breaks every check cannot
/// show that each one is needed: swift-mutation-testing turned each `&&` into
/// `||` in turn (11 mutants), and `ChaoticFixedWidth` still failed every law.
/// Each fault here breaks exactly one check and leaves the rest true, so a law
/// that dropped that check would pass it.
///
/// `Fault` is a type parameter, not a stored field, because the laws reach
/// `Value.min` and integer literals, which no generated value carries.
protocol IntegerFault: Sendable {
    /// `x.addingReportingOverflow(0)` reports overflow for a nonzero `x`.
    static var addingZeroOverflows: Bool { get }
    /// `x.subtractingReportingOverflow(0)` reports overflow for a nonzero `x`.
    static var subtractingZeroOverflows: Bool { get }
    /// `x.multipliedReportingOverflow(by: 1)` reports overflow for a nonzero `x`.
    static var multiplyingByOneOverflows: Bool { get }
    /// `min.subtractingReportingOverflow(1)` saturates at `min`, so
    /// `min &- 1 != max` while `max &+ 1 == min` still holds.
    static var minMinusOneSaturates: Bool { get }
    /// `quotientAndRemainder(dividingBy:)` gets the quotient right and the
    /// remainder one too high.
    static var remainderOffByOne: Bool { get }
}

extension IntegerFault {
    static var addingZeroOverflows: Bool { false }
    static var subtractingZeroOverflows: Bool { false }
    static var multiplyingByOneOverflows: Bool { false }
    static var minMinusOneSaturates: Bool { false }
    static var remainderOffByOne: Bool { false }
}

enum AddingZeroOverflows: IntegerFault { static var addingZeroOverflows: Bool { true } }
enum SubtractingZeroOverflows: IntegerFault { static var subtractingZeroOverflows: Bool { true } }
enum MultiplyingByOneOverflows: IntegerFault { static var multiplyingByOneOverflows: Bool { true } }
enum MinMinusOneSaturates: IntegerFault { static var minMinusOneSaturates: Bool { true } }
enum RemainderOffByOne: IntegerFault { static var remainderOffByOne: Bool { true } }

/// An `Int32` wrapper that is correct apart from its `Fault`.
struct SingleFaultInteger<Fault: IntegerFault>: FixedWidthInteger, SignedInteger, Sendable,
    CustomStringConvertible {
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

    // A generic type cannot have stored static properties.
    static var isSigned: Bool { true }
    static var bitWidth: Int { Int32.bitWidth }
    static var min: Self { Self(value: Int32.min) }
    static var max: Self { Self(value: Int32.max) }
    var bitWidth: Int { value.bitWidth }
    var trailingZeroBitCount: Int { value.trailingZeroBitCount }
    var leadingZeroBitCount: Int { value.leadingZeroBitCount }
    var nonzeroBitCount: Int { value.nonzeroBitCount }
    var words: Int32.Words { value.words }
    var magnitude: UInt32 { value.magnitude }
    var byteSwapped: Self { Self(value: value.byteSwapped) }
    var description: String { "\(Fault.self)(\(value))" }

    func hash(into hasher: inout Hasher) { value.hash(into: &hasher) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }

    func distance(to other: Self) -> Int { Int(other.value - value) }
    func advanced(by step: Int) -> Self { Self(value: value &+ Int32(step)) }
    func signum() -> Self { Self(value: value.signum()) }

    func quotientAndRemainder(dividingBy rhs: Self) -> (quotient: Self, remainder: Self) {
        let pair = value.quotientAndRemainder(dividingBy: rhs.value)
        let remainder = Fault.remainderOffByOne ? pair.remainder &+ 1 : pair.remainder
        return (Self(value: pair.quotient), Self(value: remainder))
    }

    func addingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.addingReportingOverflow(rhs.value)
        let overflow = pair.overflow || (Fault.addingZeroOverflows && rhs.value == 0 && value != 0)
        return (Self(value: pair.partialValue), overflow)
    }
    func subtractingReportingOverflow(_ rhs: Self) -> (partialValue: Self, overflow: Bool) {
        if Fault.minMinusOneSaturates, value == Int32.min, rhs.value == 1 {
            return (self, true)
        }
        let pair = value.subtractingReportingOverflow(rhs.value)
        let overflow = pair.overflow || (Fault.subtractingZeroOverflows && rhs.value == 0 && value != 0)
        return (Self(value: pair.partialValue), overflow)
    }
    func multipliedReportingOverflow(by rhs: Self) -> (partialValue: Self, overflow: Bool) {
        let pair = value.multipliedReportingOverflow(by: rhs.value)
        let overflow = pair.overflow || (Fault.multiplyingByOneOverflows && rhs.value == 1 && value != 0)
        return (Self(value: pair.partialValue), overflow)
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

/// Small values, as for the other planted integers, so no law overflows.
func singleFaultIntegers<Fault: IntegerFault>(
    _ fault: Fault.Type
) -> Generator<SingleFaultInteger<Fault>, some SendableSequenceType> {
    Gen<Int>.int(in: -50...50).map { SingleFaultInteger<Fault>(value: Int32($0)) }
}
