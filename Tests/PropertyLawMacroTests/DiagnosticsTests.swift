import PropertyLawCore
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import PropertyLawMacroImpl

struct DiagnosticsTests {

    /// Direct `#expect` pin on the dynamic `noKnownConformance` message.
    /// `assertMacroExpansion` reports message mismatches via `XCTFail`,
    /// which Swift Testing's `@Test` doesn't always pick up — so the
    /// `DiagnosticSpec` literals in the other tests can drift silently.
    /// This test catches the drift directly at the `PropertyLawDiagnostic`
    /// surface.
    @Test func noKnownConformanceMessageListsEveryRecognizedProtocol() {
        let message = PropertyLawDiagnostic.noKnownConformance.message
        for known in KnownProtocol.allCases {
            #expect(
                message.contains(known.declarationName),
                "noKnownConformance message is missing \(known.declarationName)"
            )
        }
    }

    @Test func typeWithNoStdlibConformanceEmitsWarning() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo: SomeCustomProtocol {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: SomeCustomProtocol {
                let value: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: PropertyLawDiagnostic.noKnownConformance.message,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func bareTypeNoInheritanceClauseEmitsWarning() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo {
                let value: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: PropertyLawDiagnostic.noKnownConformance.message,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    // MARK: - cannotDeriveGenerator (M3)

    @Test func plainStructWithRawMemberDerivesMemberwiseNoWarning() {
        // PRD §5.7 Strategy 3 — every stored property is a recognized raw
        // type, so memberwise derivation succeeds and no warning fires.
        // The emitter spells the zip+map composition that lifts through
        // the type's synthesized memberwise initializer.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo: Equatable {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: Equatable {
                let value: Int
            }

            struct FooPropertyLawTests {
                @Test func equatable_Foo() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Foo.self,
                        using: Gen<Int>.int().map {
                            Foo(value: $0)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func structWithUnknownTypeFiresCannotDeriveWarning() {
        // `Widget` is a bespoke type with no recognized raw / known value
        // generator, so memberwise derivation falls through to .todo and
        // the macro warns.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Doc: Equatable {
                let widget: Widget
            }
            """,
            expandedSource: """
            struct Doc: Equatable {
                let widget: Widget
            }

            struct DocPropertyLawTests {
                @Test func equatable_Doc() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Doc.self,
                        using: Doc.gen()  // TODO: no generator derived — supply `static func gen()` \
            (this line will not compile)
                    )
                }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot derive a generator for `Doc`: stored property \
                        `widget: Widget` resolves to no generator — `Widget` is not \
                        a recognized stdlib type (memberwise derivation supports \
                        Int/String/Bool/Double/Float, the fixed-width integer family, \
                        Character, and Date, plus optionals, arrays, sets, and \
                        dictionaries of those), and no generator could be derived for \
                        it from the types in scope. Provide `static func gen() -> \
                        Generator<Doc, some SendableSequenceType>`.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func structWithUserInitDerivesThroughIt() {
        // A user-defined init suppresses Swift's synthesized memberwise
        // init, so the strategist derives through the user's init instead.
        // This test was written when that fell through to a warning.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Wrapped: Equatable {
                let value: Int
                init(raw: String) { self.value = Int(raw) ?? 0 }
            }
            """,
            expandedSource: """
            struct Wrapped: Equatable {
                let value: Int
                init(raw: String) { self.value = Int(raw) ?? 0 }
            }

            struct WrappedPropertyLawTests {
                @Test func equatable_Wrapped() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Wrapped.self,
                        using: Gen<Character>.letterOrNumber.string(of: 0 ... 8).map {
                            Wrapped(raw: $0)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    /// Written when an enum that was neither `CaseIterable` nor raw-valued
    /// fell through to a warning. Enumerating its cases derives it now.
    @Test func enumWithoutCaseIterableOrRawTypeDerivesFromItsCases() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            enum Either: Equatable {
                case left, right
            }
            """,
            expandedSource: """
            enum Either: Equatable {
                case left, right
            }

            struct EitherPropertyLawTests {
                @Test func equatable_Either() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Either.self,
                        using: Gen.oneOf(
                Gen.always(Either.left).eraseToAny(),
                Gen.always(Either.right).eraseToAny()
                        )
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func caseIterableEnumDoesNotFireCannotDeriveWarning() {
        // Derivation succeeds; no warning.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            enum Status: CaseIterable, Equatable {
                case pending, active
            }
            """,
            expandedSource: """
            enum Status: CaseIterable, Equatable {
                case pending, active
            }

            struct StatusPropertyLawTests {
                @Test func equatable_Status() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Status.self,
                        using: Gen<Status?>.element(of: Status.allCases).compactMap {
                            $0
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func encodableAloneIsNotCodable() {
        // Codable requires both halves; an Encodable-only type doesn't get
        // a codable check emitted.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Halfway: Encodable {
                let id: Int
            }
            """,
            expandedSource: """
            struct Halfway: Encodable {
                let id: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: PropertyLawDiagnostic.noKnownConformance.message,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }
}
