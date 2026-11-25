/// Why a lifetime trial failed. The property throws it, so the counterexample
/// carries the reason.
struct LifetimeLawViolation: Error, CustomStringConvertible {
    let description: String
}
