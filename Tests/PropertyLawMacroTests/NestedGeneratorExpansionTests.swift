@testable import PropertyLawMacroImpl
import SwiftSyntaxMacrosTestSupport
import Testing

/// Expansions whose generator nests one multi-line expression in another,
/// laid out by `ExpressionLayout`: each site that places an expression adds
/// only its own column.
struct NestedGeneratorExpansionTests {

    /// A payload case is a `zip(...)` whose `.map` sits on the next line,
    /// nested in the `Gen.oneOf(` list: it moves 4 with its case, then 12
    /// with `using:`, so it lands under its own `zip(`. `EndToEndSignal`
    /// compiles the same shape. swift-syntax's formatter splits the closure
    /// over three lines in a macro expansion, as the Identifiable golden in
    /// `MacroExpansionTests` shows too; the discovery plugin keeps it on one.
    @Test func payloadCaseKeepsItsMapUnderItsZip() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            enum Signal: Equatable {
                case off
                case dimmed(level: Int, warm: Bool)
            }
            """,
            expandedSource: """
            enum Signal: Equatable {
                case off
                case dimmed(level: Int, warm: Bool)
            }

            struct SignalPropertyLawTests {
                @Test func equatable_Signal() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Signal.self,
                        using: Gen.oneOf(
                            Gen.always(Signal.off).eraseToAny(),
                            zip(Gen<Int>.int(), Gen<Bool>.bool())
                            .map {
                                Signal.dimmed(level: $0.0, warm: $0.1)
                            } .eraseToAny()
                        )
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
}
