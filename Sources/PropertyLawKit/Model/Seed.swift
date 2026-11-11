import Foundation
import PropertyBased

/// Opaque, replayable seed for a property law check.
///
/// Carries the four `UInt64`s that `Xoshiro` uses as its state, but exposes
/// them as named scalar fields rather than a 4-tuple. The `description` is
/// the base64 form returned by `Xoshiro.currentSeed` on Foundation platforms,
/// which makes seeds copy-pasteable from CI logs into ``Seed/init(base64:)``
/// for replay.
public struct Seed: Sendable, Hashable, CustomStringConvertible {
    public let stateA: UInt64
    public let stateB: UInt64
    public let stateC: UInt64
    public let stateD: UInt64

    public init(stateA: UInt64, stateB: UInt64, stateC: UInt64, stateD: UInt64) {
        self.stateA = stateA
        self.stateB = stateB
        self.stateC = stateC
        self.stateD = stateD
    }

    public init?(base64: String) {
        guard let rng = Xoshiro(seed: base64) else { return nil }
        let state = rng.currentState
        self.init(stateA: state.0, stateB: state.1, stateC: state.2, stateD: state.3)
    }

    public var description: String {
        makeXoshiro().currentSeed
    }

    /// Build the `Xoshiro` value the upstream API expects. Bridges between
    /// our scalar storage and the upstream's 4-tuple seed parameter; the
    /// tuple appears only as a literal expression at this single boundary.
    func makeXoshiro() -> Xoshiro {
        Xoshiro(seed: (stateA, stateB, stateC, stateD))
    }

    /// Build a `Seed` from a `Xoshiro`'s current state. Inverse of
    /// `makeXoshiro()`.
    init(xoshiro: Xoshiro) {
        let state = xoshiro.currentState
        self.init(stateA: state.0, stateB: state.1, stateC: state.2, stateD: state.3)
    }
}
