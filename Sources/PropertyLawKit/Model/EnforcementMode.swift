public enum EnforcementMode: Sendable, Hashable {
    /// Strict-tier violations throw, failing the test. Conventional and Heuristic violations do not
    /// throw: each is recorded as a Swift Testing warning, so the run prints it and the test passes.
    ///
    /// Before Swift 6.3 Swift Testing has no warning severity, and the violation is recorded as an
    /// error instead — which does mark the test failed, though nothing throws.
    case `default`

    /// All violations regardless of tier cause `checkXxxPropertyLaws` to throw.
    case strict
}

extension EnforcementMode {
    func shouldThrow(for tier: StrictnessTier) -> Bool {
        switch self {
        case .default:
            return tier == .strict
        case .strict:
            return true
        }
    }
}
