import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

/// `@Discoverable(group:)` macro expansion tests (PRD §5.5 M5 marker
/// layer). The macro emits no peer declarations — these tests pin
/// down the no-emit contract and the diagnostic that fires when
/// `group:` isn't a string literal.
struct DiscoverableMacroTests {

    /// Local registry — `assertMacroExpansion` only sees macros named
    /// here, so this suite stays decoupled from `MacroExpansionTests`'
    /// `testMacros` dictionary even if both are loaded simultaneously.
    nonisolated(unsafe) static let macros: [String: Macro.Type] = [
        "Discoverable": DiscoverableMacro.self
    ]

    @Test func bareAttributeProducesNoPeer() {
        assertMacroExpansion(
            """
            struct Codec {
                @Discoverable
                static func encode(_ x: Int) -> String { "" }
            }
            """,
            expandedSource: """
            struct Codec {
                static func encode(_ x: Int) -> String { "" }
            }
            """,
            macros: Self.macros
        )
    }

    @Test func stringLiteralGroupProducesNoPeerAndNoDiagnostic() {
        assertMacroExpansion(
            """
            struct Codec {
                @Discoverable(group: "wire")
                static func encode(_ x: Int) -> String { "" }
            }
            """,
            expandedSource: """
            struct Codec {
                static func encode(_ x: Int) -> String { "" }
            }
            """,
            macros: Self.macros
        )
    }

    @Test func nonLiteralGroupArgumentEmitsWarning() {
        assertMacroExpansion(
            """
            let groupName = "wire"
            struct Codec {
                @Discoverable(group: groupName)
                static func encode(_ x: Int) -> String { "" }
            }
            """,
            expandedSource: """
            let groupName = "wire"
            struct Codec {
                static func encode(_ x: Int) -> String { "" }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        @Discoverable(group:) requires a string literal — the \
                        discovery plugin reads the value at scan time and can't \
                        evaluate variable references or computed strings. \
                        Replace with an inline string literal so the function is \
                        matched by group-based round-trip discovery.
                        """,
                    line: 3,
                    column: 26,
                    severity: .warning
                )
            ],
            macros: Self.macros
        )
    }
}
