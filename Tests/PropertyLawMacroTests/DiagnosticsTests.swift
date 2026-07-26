import PropertyLawCore
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

// One test per derivation-strategy diagnostic; the suite legitimately
// grows past SwiftLint's default body-length threshold as derivation
// strategies ship. Disable is paired with an explicit re-enable at
// end of file.
// swiftlint:disable type_body_length

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
                    message: """
                        Type has no recognized stdlib protocol conformance — no \
                        law checks emitted. Recognized protocols: Equatable, \
                        Hashable, Comparable, Codable, IteratorProtocol, Sequence, \
                        Collection, BidirectionalCollection, RandomAccessCollection, \
                        MutableCollection, RangeReplaceableCollection, SetAlgebra, \
                        Strideable, RawRepresentable, LosslessStringConvertible, \
                        Identifiable, CaseIterable. Conformances declared via \
                        extensions outside the type's primary declaration aren't \
                        visible to the macro (it sees only the decoratee's syntax); \
                        whole-module discovery (PRD §5.3) handles those cases.
                        """,
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
                    message: """
                        Type has no recognized stdlib protocol conformance — no \
                        law checks emitted. Recognized protocols: Equatable, \
                        Hashable, Comparable, Codable, IteratorProtocol, Sequence, \
                        Collection, BidirectionalCollection, RandomAccessCollection, \
                        MutableCollection, RangeReplaceableCollection, SetAlgebra, \
                        Strideable, RawRepresentable, LosslessStringConvertible, \
                        Identifiable, CaseIterable. Conformances declared via \
                        extensions outside the type's primary declaration aren't \
                        visible to the macro (it sees only the decoratee's syntax); \
                        whole-module discovery (PRD §5.3) handles those cases.
                        """,
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
                            using: Gen<Int>.int().map { Foo(value: $0) }
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
                            using: Doc.gen()
                        )
                    }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot derive a generator for `Doc`: stored property \
                        `widget: Widget` has no recognized stdlib raw type \
                        (memberwise derivation supports Int/String/Bool/Double/Float \
                        and the fixed-width integer family). Provide `static func \
                        gen() -> Generator<Doc, some SendableSequenceType>`.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func structWithUserInitFiresCannotDeriveWarning() {
        // A user-defined init suppresses Swift's synthesized memberwise
        // init — strategist falls through and the macro warns.
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
                            using: Wrapped.gen()
                        )
                    }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot derive a generator for `Wrapped`: the type declares \
                        a user `init(...)` in its primary body, which suppresses \
                        Swift's synthesized memberwise initializer. Provide \
                        `static func gen() -> Generator<Wrapped, some \
                        SendableSequenceType>`.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }

    @Test func enumWithoutCaseIterableOrRawTypeFiresCannotDeriveWarning() {
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
                            using: Either.gen()
                        )
                    }
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: """
                        Cannot derive a generator for `Either`: not `CaseIterable` \
                        and no recognized stdlib raw type. Provide `static func \
                        gen() -> Generator<Either, some SendableSequenceType>` or \
                        add `: CaseIterable`.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
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
                            using: Gen<Status?>.element(of: Status.allCases).compactMap { $0 }
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
                    message: """
                        Type has no recognized stdlib protocol conformance — no \
                        law checks emitted. Recognized protocols: Equatable, \
                        Hashable, Comparable, Codable, IteratorProtocol, Sequence, \
                        Collection, BidirectionalCollection, RandomAccessCollection, \
                        MutableCollection, RangeReplaceableCollection, SetAlgebra, \
                        Strideable, RawRepresentable, LosslessStringConvertible, \
                        Identifiable, CaseIterable. Conformances declared via \
                        extensions outside the type's primary declaration aren't \
                        visible to the macro (it sees only the decoratee's syntax); \
                        whole-module discovery (PRD §5.3) handles those cases.
                        """,
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: testMacros
        )
    }
}

// swiftlint:enable type_body_length
