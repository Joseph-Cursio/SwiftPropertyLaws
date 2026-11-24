/// Thrown by `checkEveryCarrier` when the suite closure throws, for one
/// carrier, anything other than a `PropertyLawViolation`.
///
/// A suite that throws tested nothing for that carrier, so the walk stops
/// there rather than counting the carrier as visited. `carrier` is the
/// carrier's address in its `Enumeration`, in the same form a
/// counterexample names it; `underlying` is what the suite threw.
///
/// Cancellation, a failed `#require` and a replay mismatch are not wrapped;
/// they reach the caller as thrown.
public struct CarrierSuiteError: Error, Sendable, CustomStringConvertible {
    public let carrier: String
    public let underlying: any Error

    public init(carrier: String, underlying: any Error) {
        self.carrier = carrier
        self.underlying = underlying
    }

    public var description: String {
        "checkEveryCarrier: the suite threw for carrier \(carrier): \(underlying)"
    }
}
