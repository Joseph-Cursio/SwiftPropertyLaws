/// Replay-strictness policy for `LawCheckOptions.expectedReplayEnvironment`.
/// Defaults to `.exact`; relaxations are escape hatches for legitimate
/// toolchain bumps where the seed is still expected to be deterministic.
public enum EnvironmentRelaxation: Sendable, Hashable {
    /// Every fingerprint field must match.
    case exact

    /// Only the backend identity must match. Useful when bumping the Swift
    /// toolchain across a CI run on a backend whose RNG didn't change.
    case matchBackendOnly

    /// Only the Swift version must match. Useful when swapping backends in
    /// development and the test is generator-schema-stable.
    case matchSwiftVersionOnly

    func matches(expected: Environment, actual: Environment) -> Bool {
        switch self {
        case .exact:
            return expected == actual

        case .matchBackendOnly:
            return expected.backendIdentity == actual.backendIdentity

        case .matchSwiftVersionOnly:
            return expected.swiftVersion == actual.swiftVersion
        }
    }
}

/// Thrown when a caller asks the kit to replay against an environment
/// fingerprint that doesn't match the live one (PRD §4.6).
///
/// The PRD's failure mode this guards against: a CI artifact stored months
/// earlier carries `seed = "..."` recorded under Swift 6.1 + backend X. A
/// replay run on Swift 6.2 + backend Y, with the same seed string but a
/// different RNG-feeding generator schema, would silently re-roll a
/// *different* test under the same seed label. The mismatch is loud rather
/// than silent.
public struct ReplayEnvironmentMismatch: Error, Sendable, CustomStringConvertible {
    public let expected: Environment
    public let actual: Environment

    public init(expected: Environment, actual: Environment) {
        self.expected = expected
        self.actual = actual
    }

    public var description: String {
        var diffs: [String] = []
        if expected.swiftVersion != actual.swiftVersion {
            diffs.append("swiftVersion: \(expected.swiftVersion) → \(actual.swiftVersion)")
        }
        if expected.backendIdentity != actual.backendIdentity {
            diffs.append("backend: \(expected.backendIdentity) → \(actual.backendIdentity)")
        }
        if expected.generatorSchemaHash != actual.generatorSchemaHash {
            diffs.append(
                "generatorSchema: \(expected.generatorSchemaHash) → \(actual.generatorSchemaHash)"
            )
        }
        let body = diffs.isEmpty ? "<no field-level diff>" : diffs.joined(separator: "; ")
        return "ReplayEnvironmentMismatch — \(body)"
    }
}
