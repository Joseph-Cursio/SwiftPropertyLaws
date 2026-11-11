import PropertyBased

/// Violates Strideable.selfDistanceIsZero. `distance(to: y)` lies only when
/// `y == self`, so non-self distances stay consistent — letting us assert
/// the framework specifically catches the self-distance law.
struct LyingSelfDistance: Strideable, Sendable, CustomStringConvertible {
    typealias Stride = Int

    let value: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    func distance(to other: Self) -> Int {
        if value == other.value { return 1 }
        return other.value - value
    }

    func advanced(by step: Int) -> Self {
        Self(value: value + step)
    }

    var description: String { "LSD(\(value))" }
}

/// Violates Strideable.distanceRoundTrip and advanceRoundTrip. `advanced(by:)`
/// adds one extra step on every call, so `advance(distance(x, y))` lands at
/// `y + 1` instead of `y`, and `distance(x, advance(x, n))` measures `n + 1`.
struct OffByOneAdvance: Strideable, Sendable, CustomStringConvertible {
    typealias Stride = Int

    let value: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    func distance(to other: Self) -> Int {
        other.value - value
    }

    func advanced(by step: Int) -> Self {
        Self(value: value + step + 1)
    }

    var description: String { "OBA(\(value))" }
}

/// Violates Strideable.zeroAdvanceIdentity (and, on rare samples,
/// distanceRoundTrip/advanceRoundTrip too). `advanced(by: 0)` jumps by one
/// instead of staying in place, while non-zero advances are correct.
struct ZeroAdvanceJump: Strideable, Sendable, CustomStringConvertible {
    typealias Stride = Int

    let value: Int

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.value == rhs.value
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.value < rhs.value
    }

    func distance(to other: Self) -> Int {
        other.value - value
    }

    func advanced(by step: Int) -> Self {
        if step == 0 { return Self(value: value + 1) }
        return Self(value: value + step)
    }

    var description: String { "ZAJ(\(value))" }
}

extension Gen where Value == ZeroAdvanceJump {
    static func zeroAdvanceJump() -> Generator<ZeroAdvanceJump, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { ZeroAdvanceJump(value: $0) }
    }
}

extension Gen where Value == LyingSelfDistance {
    static func lyingSelfDistance() -> Generator<LyingSelfDistance, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { LyingSelfDistance(value: $0) }
    }
}

extension Gen where Value == OffByOneAdvance {
    static func offByOneAdvance() -> Generator<OffByOneAdvance, some SendableSequenceType> {
        Gen<Int>.int(in: -50...50).map { OffByOneAdvance(value: $0) }
    }
}
