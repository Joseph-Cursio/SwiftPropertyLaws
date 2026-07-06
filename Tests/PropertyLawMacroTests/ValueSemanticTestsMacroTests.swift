import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

/// v3.6.0 — golden-output tests for the `@ValueSemanticTests` peer macro: the
/// emitted copy-mutate-compare suite + the no-conformance diagnostic path.

nonisolated(unsafe) let valueSemanticTestsMacros: [String: Macro.Type] = [
    "ValueSemanticTests": ValueSemanticTestsMacro.self
]

struct ValueSemanticTestsMacroTests {

    @Test func emitsCopyMutateCompareSuite() {
        assertMacroExpansion(
            """
            @ValueSemanticTests
            struct Buffer: ValueSemantic {
                static func makeProbe() -> Buffer { Buffer() }
                enum Mutation: CaseIterable, Sendable { case appendOne }
                static func apply(_ mutation: Mutation, to target: inout Buffer) {}
            }
            """,
            expandedSource: """
            struct Buffer: ValueSemantic {
                static func makeProbe() -> Buffer { Buffer() }
                enum Mutation: CaseIterable, Sendable { case appendOne }
                static func apply(_ mutation: Mutation, to target: inout Buffer) {}
            }

            struct BufferValueSemanticTests {
                @Test func valueSemantic_Buffer() async throws {
                        try await checkValueSemanticPropertyLaws(for: Buffer.self)
                    }
            }
            """,
            macros: valueSemanticTestsMacros
        )
    }

    @Test func diagnosesMissingConformance() {
        assertMacroExpansion(
            """
            @ValueSemanticTests
            struct NotConforming {
            }
            """,
            expandedSource: """
            struct NotConforming {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@ValueSemanticTests requires the decoratee to conform to "
                        + "ValueSemantic in its primary declaration's inheritance clause. "
                        + "Conformances declared via extensions outside the type's "
                        + "primary declaration aren't visible to the macro.",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: valueSemanticTestsMacros
        )
    }
}
