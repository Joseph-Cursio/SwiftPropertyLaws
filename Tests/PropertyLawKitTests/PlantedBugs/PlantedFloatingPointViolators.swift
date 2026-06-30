import PropertyBased

// This conformer mirrors the FloatingPoint surface, which mandates short
// identifiers (`pi`, the `x` / `y` operands of `minimum` / `maximum`); the
// single-character backing store `v` keeps the forwarding boilerplate compact.
// swiftlint:disable identifier_name

// FloatingPoint / BinaryFloatingPoint laws can only fail on a custom
// conformer — `Double` and `Float` satisfy every IEEE-754 law. `BrokenFloat`
// wraps a `Double` and forwards the entire (large) protocol surface honestly,
// then plants a handful of scoped bugs so that each FloatingPoint and
// BinaryFloatingPoint law's counterexample-formatting path executes in one run.
//
// Plants (each chosen to break exactly the laws it targets):
//   • `isInfinite`  → false        : infinityIsInfinite
//   • `isZero`      → false        : zeroIsZero
//   • `isNaN`       → false        : nanIsNaN, nanPropagatesAddition,
//                                    nanPropagatesMultiplication
//   • `round(_:)`   → +1           : roundedZeroIdentity
//   • `negate()`/-  → affine -v+1  : signedZeroEquality, additiveInverseFinite
//   • `nextUp`      → identity      : nextUpDownRoundTrip
//   • `sign`        → .minus        : signMatchesIsLessThanZero,
//                                    significandExponentReconstruction
//   • `magnitude`   → -1           : absoluteValueNonNegative, binadeMembership
//   • `==`          → NaN-equal     : nanInequality
//   • `<`           → scoped lies   : negativeInfinityComparison,
//                                    nanComparisonIsUnordered
//   • `radix`       → 10           : radix2Constraint
//   • `init(exactly:)` of integers → +1 : convertingFromIntegerExactness
struct BrokenFloat: BinaryFloatingPoint, Sendable, CustomStringConvertible {
    typealias Exponent = Int
    typealias RawSignificand = UInt64
    typealias RawExponent = UInt
    typealias FloatLiteralType = Double
    typealias IntegerLiteralType = Int

    var v: Double

    init(_ value: Double) { self.v = value }
    init(value: Double) { self.v = value }

    // MARK: Literal / integer conversions

    init(floatLiteral value: Double) { self.v = value }
    init(integerLiteral value: Int) { self.v = Double(value) }
    init<Source: BinaryInteger>(_ source: Source) { self.v = Double(source) }
    init<Source: BinaryFloatingPoint>(_ source: Source) { self.v = Double(source) }

    /// Plant: integer conversion is off by one, so the round-trip through
    /// `Int(exactly:)` no longer recovers the original integer.
    init?<Source: BinaryInteger>(exactly source: Source) {
        guard let exact = Double(exactly: source) else { return nil }
        self.v = exact + 1
    }

    // MARK: IEEE-754 component constructors (honest forwards)

    init(sign: FloatingPointSign, exponent: Int, significand: BrokenFloat) {
        self.v = Double(sign: sign, exponent: exponent, significand: significand.v)
    }
    init(sign: FloatingPointSign, exponentBitPattern: UInt, significandBitPattern: UInt64) {
        self.v = Double(
            sign: sign,
            exponentBitPattern: exponentBitPattern,
            significandBitPattern: significandBitPattern
        )
    }
    init(signOf: BrokenFloat, magnitudeOf: BrokenFloat) {
        self.v = Double(signOf: signOf.v, magnitudeOf: magnitudeOf.v)
    }

    // MARK: Static constants (honest forwards)

    static var radix: Int { 10 }                              // plant
    static var nan: BrokenFloat { BrokenFloat(Double.nan) }
    static var signalingNaN: BrokenFloat { BrokenFloat(Double.signalingNaN) }
    static var infinity: BrokenFloat { BrokenFloat(Double.infinity) }
    static var greatestFiniteMagnitude: BrokenFloat { BrokenFloat(Double.greatestFiniteMagnitude) }
    static var pi: BrokenFloat { BrokenFloat(Double.pi) }
    static var leastNormalMagnitude: BrokenFloat { BrokenFloat(Double.leastNormalMagnitude) }
    static var leastNonzeroMagnitude: BrokenFloat { BrokenFloat(Double.leastNonzeroMagnitude) }
    static var exponentBitCount: Int { Double.exponentBitCount }
    static var significandBitCount: Int { Double.significandBitCount }

    // MARK: Instance properties (mostly honest forwards)

    var exponent: Int { v.exponent }
    var significand: BrokenFloat { BrokenFloat(v.significand) }
    var ulp: BrokenFloat { BrokenFloat(v.ulp) }
    var sign: FloatingPointSign { .minus }                    // plant
    var magnitude: BrokenFloat { BrokenFloat(-1) }            // plant
    var nextUp: BrokenFloat { self }                          // plant
    var nextDown: BrokenFloat { BrokenFloat(v.nextDown) }
    var binade: BrokenFloat { BrokenFloat(v.binade) }
    var significandWidth: Int { v.significandWidth }
    var exponentBitPattern: UInt { v.exponentBitPattern }
    var significandBitPattern: UInt64 { v.significandBitPattern }
    var bitPattern: UInt64 { v.bitPattern }

    var isNormal: Bool { v.isNormal }
    var isFinite: Bool { v.isFinite }
    var isZero: Bool { false }                                // plant
    var isSubnormal: Bool { v.isSubnormal }
    var isInfinite: Bool { false }                            // plant
    var isNaN: Bool { false }                                 // plant
    var isSignalingNaN: Bool { v.isSignalingNaN }
    var isCanonical: Bool { v.isCanonical }
    var floatingPointClass: FloatingPointClassification { v.floatingPointClass }

    var description: String { "BrokenFloat(\(v))" }

    // MARK: Arithmetic (honest forwards)

    static func + (lhs: Self, rhs: Self) -> Self { Self(lhs.v + rhs.v) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(lhs.v - rhs.v) }
    static func * (lhs: Self, rhs: Self) -> Self { Self(lhs.v * rhs.v) }
    static func / (lhs: Self, rhs: Self) -> Self { Self(lhs.v / rhs.v) }
    static func += (lhs: inout Self, rhs: Self) { lhs.v += rhs.v }
    static func -= (lhs: inout Self, rhs: Self) { lhs.v -= rhs.v }
    static func *= (lhs: inout Self, rhs: Self) { lhs.v *= rhs.v }
    static func /= (lhs: inout Self, rhs: Self) { lhs.v /= rhs.v }

    /// Plant: affine negation. `-x = -v + 1`, breaking signed-zero equality
    /// and the finite additive-inverse law without disturbing `+`.
    static prefix func - (operand: Self) -> Self { Self(-operand.v + 1) }
    mutating func negate() { v = -v + 1 }

    mutating func formRemainder(dividingBy other: Self) { v.formRemainder(dividingBy: other.v) }
    mutating func formTruncatingRemainder(dividingBy other: Self) {
        v.formTruncatingRemainder(dividingBy: other.v)
    }
    mutating func formSquareRoot() { v.formSquareRoot() }
    mutating func addProduct(_ lhs: Self, _ rhs: Self) { v.addProduct(lhs.v, rhs.v) }

    /// Plant: rounding shifts by one, so `zero.rounded()` is no longer zero.
    mutating func round(_ rule: FloatingPointRoundingRule) {
        v.round(rule)
        v += 1
    }

    static func minimum(_ x: Self, _ y: Self) -> Self { Self(Double.minimum(x.v, y.v)) }
    static func maximum(_ x: Self, _ y: Self) -> Self { Self(Double.maximum(x.v, y.v)) }
    static func minimumMagnitude(_ x: Self, _ y: Self) -> Self { Self(Double.minimumMagnitude(x.v, y.v)) }
    static func maximumMagnitude(_ x: Self, _ y: Self) -> Self { Self(Double.maximumMagnitude(x.v, y.v)) }

    // MARK: Comparison

    /// Plant: NaN compares equal to NaN, so the NaN-inequality law fails.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.v == rhs.v || (lhs.v.isNaN && rhs.v.isNaN)
    }
    func hash(into hasher: inout Hasher) { hasher.combine(v) }

    /// Plant: a NaN left operand reports "less than" everything (breaking the
    /// unordered law) and `-inf < +inf` is forced false (breaking the
    /// negative-infinity comparison); all other comparisons are honest.
    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.v.isNaN { return true }
        if lhs.v == -.infinity && rhs.v == .infinity { return false }
        return lhs.v < rhs.v
    }

    func isEqual(to other: Self) -> Bool { self == other }
    func isLess(than other: Self) -> Bool { self < other }
    func isLessThanOrEqualTo(_ other: Self) -> Bool { self < other || self == other }

    // MARK: Strideable (honest forwards)

    func distance(to other: Self) -> Self { Self(other.v - v) }
    func advanced(by amount: Self) -> Self { Self(v + amount.v) }
}

extension Gen where Value == BrokenFloat {
    /// Finite samples in a modest range — the NaN-domain laws build `Self.nan`
    /// themselves, so the generator never needs to emit non-finite values.
    static func brokenFloat() -> Generator<BrokenFloat, some SendableSequenceType> {
        Gen<Double>.double(in: -1_000.0...1_000.0).map { BrokenFloat($0) }
    }
}

// swiftlint:enable identifier_name
