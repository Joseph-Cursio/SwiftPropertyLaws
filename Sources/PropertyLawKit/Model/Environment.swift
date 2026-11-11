// Environment fingerprint per PRD §4.6.
//
// Records `swiftVersion`, `backendIdentity`, and `generatorSchemaHash`. The
// backend identity arrives via `PropertyBackend.identifier` from M4 onward;
// the generator registry doesn't exist until PropertyLawMacro lands, so the
// schema hash ships a placeholder. Replay-mismatch validation logic is M5
// scope — recording the fingerprint now lets seeds carried in CI artifacts
// remain meaningful once the validator lands, without a breaking API change.

public struct Environment: Sendable, Hashable, Codable {
    public let swiftVersion: String
    public let backendIdentity: String
    public let generatorSchemaHash: String

    public init(swiftVersion: String, backendIdentity: String, generatorSchemaHash: String) {
        self.swiftVersion = swiftVersion
        self.backendIdentity = backendIdentity
        self.generatorSchemaHash = generatorSchemaHash
    }

    /// Default environment, fingerprinted against the default backend
    /// (`SwiftPropertyBasedBackend`). Used by tests that construct
    /// `CheckResult` literals; production paths go through
    /// `Environment.current(backend:)` so the recorded backend matches the
    /// one that actually ran the check.
    public static var current: Self {
        Self(
            swiftVersion: detectedSwiftVersion,
            backendIdentity: SwiftPropertyBasedBackend().identifier,
            generatorSchemaHash: "m1-no-registry"
        )
    }

    public static func current(backend: any PropertyBackend) -> Self {
        Self(
            swiftVersion: detectedSwiftVersion,
            backendIdentity: backend.identifier,
            generatorSchemaHash: "m1-no-registry"
        )
    }
}

private let detectedSwiftVersion: String = {
    #if swift(>=6.3)
    return "6.3+"
    #elseif swift(>=6.2)
    return "6.2"
    #elseif swift(>=6.1)
    return "6.1"
    #else
    return "<6.1"
    #endif
}()
