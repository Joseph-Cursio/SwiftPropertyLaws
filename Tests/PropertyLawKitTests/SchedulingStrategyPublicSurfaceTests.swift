import PropertyLawKit
import Testing

/// Proves the scheduling option is reachable from the public surface.
/// **Intentionally uses plain `import PropertyLawKit`** (not `@testable`), the
/// same posture as `DownstreamPropertyBackendSmokeTests`: if `SchedulingStrategy`,
/// `LawCheckOptions.scheduling` or `Environment.scheduling` stop being public, or
/// the labelled initialisers callers already use stop compiling, this file fails
/// to build.
@Suite("SchedulingStrategy — public surface")
struct SchedulingStrategyPublicSurfaceTests {

    @Test
    func strategiesAndTheirNamesArePublic() {
        let strategies: [SchedulingStrategy] = [.fifo, .seeded]
        #expect(strategies.map(\.description) == ["fifo", "seeded"])
        #expect(strategies.map(\.identifier) == [nil, "seeded/1"])
        #expect(Set(strategies).count == 2)
    }

    @Test
    func optionsCarryTheStrategy() {
        var options = LawCheckOptions(budget: .sanity, scheduling: .seeded)
        #expect(options.scheduling == .seeded)
        options.scheduling = .fifo
        #expect(options.scheduling == .fifo)
        #expect(LawCheckOptions().scheduling == .fifo)
    }

    /// The labelled shapes downstream callers use (SwiftInferProperties emits
    /// `LawCheckOptions(suppressions:)`) still compile with the new trailing parameter.
    @Test
    func existingLabelledInitialisersStillCompile() {
        #expect(LawCheckOptions(suppressions: []).scheduling == .fifo)
        #expect(LawCheckOptions(budget: .sanity).scheduling == .fifo)
        #expect(LawCheckOptions(budget: .sanity, equalValuePairing: .independent).scheduling == .fifo)
    }

    @Test
    func environmentCarriesTheStrategy() {
        let old = Environment(swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash")
        let seeded = Environment(
            swiftVersion: "6.2", backendIdentity: "backend", generatorSchemaHash: "hash", scheduling: "seeded/1"
        )
        #expect(old.scheduling == nil)
        #expect(seeded.scheduling == "seeded/1")
        #expect(old != seeded)
        #expect(Environment.current.scheduling == nil)
    }
}
