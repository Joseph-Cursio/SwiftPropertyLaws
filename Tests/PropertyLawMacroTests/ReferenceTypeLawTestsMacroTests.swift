import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

/// v3.9.0 — golden-output tests for the reference-type law test macros,
/// `@DefensiveCopyTests` + `@StableIdentityTests` (they share
/// `LawTestPeerMacro` with `@ValueSemanticTests`).

nonisolated(unsafe) let referenceTypeLawMacros: [String: Macro.Type] = [
    "DefensiveCopyTests": DefensiveCopyTestsMacro.self,
    "StableIdentityTests": StableIdentityTestsMacro.self
]

struct ReferenceTypeLawTestsMacroTests {

    @Test func defensiveCopyEmitsSuite() {
        assertMacroExpansion(
            """
            @DefensiveCopyTests
            final class Buffer: DefensiveCopy {
            }
            """,
            expandedSource: """
            final class Buffer: DefensiveCopy {
            }

            struct BufferDefensiveCopyTests {
                @Test func defensiveCopy_Buffer() async throws {
                        try await checkDefensiveCopyPropertyLaws(for: Buffer.self)
                    }
            }
            """,
            macros: referenceTypeLawMacros
        )
    }

    @Test func stableIdentityEmitsSuite() {
        assertMacroExpansion(
            """
            @StableIdentityTests
            final class Node: StableIdentity {
            }
            """,
            expandedSource: """
            final class Node: StableIdentity {
            }

            struct NodeStableIdentityTests {
                @Test func stableIdentity_Node() async throws {
                        try await checkStableIdentityPropertyLaws(for: Node.self)
                    }
            }
            """,
            macros: referenceTypeLawMacros
        )
    }

    @Test func diagnosesMissingDefensiveCopyConformance() {
        assertMacroExpansion(
            """
            @DefensiveCopyTests
            final class NotConforming {
            }
            """,
            expandedSource: """
            final class NotConforming {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@DefensiveCopyTests requires the decoratee to conform to "
                        + "DefensiveCopy in its primary declaration's inheritance clause. "
                        + "Conformances declared via extensions outside the type's "
                        + "primary declaration aren't visible to the macro.",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: referenceTypeLawMacros
        )
    }
}
