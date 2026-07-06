import Testing
import PropertyBased
@testable import PropertyLawKit

/// v3.8.0 — tests for `checkStableIdentityPropertyLaws`. Two hand-rolled class
/// conformers: an identity keyed on an immutable field whose mutation touches
/// only non-identity state (positive control), and one whose `==` / `hash` read
/// a mutable field a mutation changes (negative control). Mirrors pbt-book
/// Chapter 9 §9.3.3.
struct StableIdentityLawsTests {

    @Test func stableIdentityPassesBothLaws() async throws {
        let results = try await checkStableIdentityPropertyLaws(
            for: StableId.self,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results.allSatisfy { $0.tier == .strict })
        #expect(results.map(\.protocolLaw) == [
            "StableIdentity.hashStableUnderMutation",
            "StableIdentity.equalityStableUnderMutation"
        ])
    }

    @Test func mutableHashKeyIsDetected() async throws {
        // `==` / `hash` read a mutable `name` a mutation changes → both laws fail.
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkStableIdentityPropertyLaws(
                for: UnstableId.self,
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }
}

// MARK: - Fixtures: stable identity (positive control)

final class StableId: StableIdentity, @unchecked Sendable {
    let id: Int
    var label: String = ""

    init() { id = 0 }

    static func == (lhs: StableId, rhs: StableId) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func makeProbe() -> StableId { StableId() }

    enum Mutation: CaseIterable, Sendable { case relabel }

    static func apply(_ mutation: Mutation, to target: StableId) {
        switch mutation {
        // Touches only non-identity state — hash / == unaffected.
        case .relabel: target.label = "x"
        }
    }
}

// MARK: - Fixtures: mutable hash key (negative control)

final class UnstableId: StableIdentity, @unchecked Sendable {
    var name: String = "init"

    static func == (lhs: UnstableId, rhs: UnstableId) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }

    static func makeProbe() -> UnstableId { UnstableId() }

    enum Mutation: CaseIterable, Sendable { case rename }

    static func apply(_ mutation: Mutation, to target: UnstableId) {
        switch mutation {
        // Mutates a field that `==` / `hash` read → identity is not stable.
        case .rename: target.name = "changed"
        }
    }
}
