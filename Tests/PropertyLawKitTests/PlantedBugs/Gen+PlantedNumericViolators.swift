import PropertyBased

/// Violates `Numeric.oneMultiplicativeIdentity`. `* 1` returns `value + 1`
/// instead of `value`. Other Numeric laws hold for non-1 multipliers.
struct BrokenOneIdentity: Numeric, Sendable, CustomStringConvertible {
    let value: Int

    init(value: Int) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }

    var magnitude: Int { abs(value) }

    static let zero = Self(value: 0)

    static func + (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value + rhs.value) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value - rhs.value) }

    static func * (lhs: Self, rhs: Self) -> Self {
        if rhs.value == 1 { return Self(value: lhs.value + 1) }
        if lhs.value == 1 { return Self(value: rhs.value + 1) }
        return Self(value: lhs.value * rhs.value)
    }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }

    var description: String { "BOI(\(value))" }
}

/// Violates `Numeric.multiplicationCommutativity` (and incidentally
/// associativity on some triples). `*` adds an asymmetric correction
/// term — `lhs.value * rhs.value + lhs.value` — so `a * b ≠ b * a`
/// whenever `a ≠ b`. AdditiveArithmetic + identity + zero-annihilation
/// laws still hold because `+` and `* 0` are unmodified.
struct NonCommutativeMultiply: Numeric, Sendable, CustomStringConvertible {
    let value: Int

    init(value: Int) { self.value = value }
    init(integerLiteral value: Int) { self.value = value }
    init?<T: BinaryInteger>(exactly source: T) {
        guard let candidate = Int(exactly: source) else { return nil }
        self.value = candidate
    }

    var magnitude: Int { abs(value) }

    static let zero = Self(value: 0)

    static func + (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value + rhs.value) }
    static func - (lhs: Self, rhs: Self) -> Self { Self(value: lhs.value - rhs.value) }

    static func * (lhs: Self, rhs: Self) -> Self {
        if lhs.value == 0 || rhs.value == 0 { return Self(value: 0) }
        // Asymmetric — adds lhs but not rhs, breaking commutativity for
        // every non-zero, non-equal pair.
        return Self(value: lhs.value * rhs.value + lhs.value)
    }
    static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }

    var description: String { "NCM(\(value))" }
}

extension Gen where Value == NonCommutativeMultiply {
    static func nonCommutativeMultiply() -> Generator<NonCommutativeMultiply, some SendableSequenceType> {
        Gen<Int>.int(in: -10...10).map { NonCommutativeMultiply(value: $0) }
    }
}

extension Gen where Value == BrokenOneIdentity {
    static func brokenOneIdentity() -> Generator<BrokenOneIdentity, some SendableSequenceType> {
        Gen<Int>.int(in: -10...10).map { BrokenOneIdentity(value: $0) }
    }
}
