// Environment fingerprint per PRD §4.6.
//
// Records `swiftVersion`, `backendIdentity`, `generatorSchemaHash` and, for a
// virtual-time suite run under a non-FIFO strategy, `scheduling`. The
// backend identity arrives via `PropertyBackend.identifier` from M4 onward;
// the generator registry doesn't exist until PropertyLawMacro lands, so the
// schema hash ships a placeholder. Replay-mismatch validation logic is M5
// scope — recording the fingerprint now lets seeds carried in CI artifacts
// remain meaningful once the validator lands, without a breaking API change.

public struct Environment: Sendable, Hashable, Codable {
    public let swiftVersion: String
    public let backendIdentity: String
    public let generatorSchemaHash: String

    /// The scheduling strategy's stable `SchedulingStrategy.identifier`, such
    /// as `"seeded/1"`, or `nil` for FIFO.
    ///
    /// `nil` whenever the suite does not honour the strategy (every suite
    /// outside virtual time), so a sync law run with `.seeded` records the
    /// same fingerprint as under `.fifo`. Optional, so a fingerprint encoded
    /// before this field existed decodes (as FIFO) and still compares equal.
    /// Every `EnvironmentRelaxation` requires it to match.
    public let scheduling: String?

    public init(
        swiftVersion: String,
        backendIdentity: String,
        generatorSchemaHash: String,
        scheduling: String? = nil
    ) {
        self.swiftVersion = swiftVersion
        self.backendIdentity = backendIdentity
        self.generatorSchemaHash = generatorSchemaHash
        self.scheduling = scheduling
    }

    /// Default environment, fingerprinted against the default backend
    /// (`SwiftPropertyBasedBackend`). Used by tests that construct
    /// `CheckResult` literals; production paths go through
    /// `Environment.current(backend:)` (through the options-aware constructor
    /// the drivers share) so the recorded backend matches the
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

    /// The fingerprint every driver stamps and `ReplayEnvironmentValidator`
    /// checks against: `current(backend: options.backend)`, plus the
    /// scheduling identifier when the suite honours the strategy
    /// (`options.schedulingIsInEffect`). Stamping and checking share this one
    /// function so they apply the same rule.
    package static func current(options: LawCheckOptions) -> Self {
        let base = current(backend: options.backend)
        return Self(
            swiftVersion: base.swiftVersion,
            backendIdentity: base.backendIdentity,
            generatorSchemaHash: base.generatorSchemaHash,
            scheduling: options.schedulingIsInEffect ? options.scheduling.identifier : nil
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
