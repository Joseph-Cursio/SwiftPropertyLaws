import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

struct MacroExpansionMultiTypeTests {

    @Test func setAlgebraEmitsBothEquatableAndSetAlgebra() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Bag: SetAlgebra, Equatable {
                init() {}
            }
            """,
            expandedSource: """
            struct Bag: SetAlgebra, Equatable {
                init() {}
            }

            struct BagPropertyLawTests {
                @Test func equatable_Bag() async throws {
                        try await checkEquatablePropertyLaws(
                            for: Bag.self,
                            using: Bag.gen()
                        )
                    }

                @Test func setAlgebra_Bag() async throws {
                        try await checkSetAlgebraPropertyLaws(
                            for: Bag.self,
                            using: Bag.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func iteratorProtocolOnlyEmitsNothingAndWarns() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
            }
            """,
            expandedSource: """
            struct Cursor: IteratorProtocol {
                mutating func next() -> Int? { nil }
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

    @Test func unconditionalSendableConformanceIsIgnored() {
        // Sendable + custom protocols are silently ignored; recognized
        // stdlib protocols still surface.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo: Sendable, MyCustomProto, Equatable {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: Sendable, MyCustomProto, Equatable {
                let value: Int
            }

            struct FooPropertyLawTests {
                @Test func equatable_Foo() async throws {
                        try await checkEquatablePropertyLaws(
                            for: Foo.self,
                            using: Foo.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func encodableDecodablePairResolvesToCodable() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Record: Encodable, Decodable, Equatable {
                let id: Int
            }
            """,
            expandedSource: """
            struct Record: Encodable, Decodable, Equatable {
                let id: Int
            }

            struct RecordPropertyLawTests {
                @Test func equatable_Record() async throws {
                        try await checkEquatablePropertyLaws(
                            for: Record.self,
                            using: Record.gen()
                        )
                    }

                @Test func codable_Record() async throws {
                        try await checkCodablePropertyLaws(
                            for: Record.self,
                            using: Record.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func stringRawRepresentableEnumDerivesGenerator() {
        // M3: enum + recognized stdlib raw type → derived generator
        // (Gen.<RawType>...compactMap { TypeName(rawValue: $0) }) instead
        // of the user's <TypeName>.gen() reference.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            enum Direction: String, Codable, Equatable {
                case north, south, east, west
            }
            """,
            expandedSource: """
            enum Direction: String, Codable, Equatable {
                case north, south, east, west
            }

            struct DirectionPropertyLawTests {
                @Test func equatable_Direction() async throws {
                        try await checkEquatablePropertyLaws(
                            for: Direction.self,
                            using: Gen<Character>.letterOrNumber.string(of: 0...8)
                                .compactMap { Direction(rawValue: $0) }
                        )
                    }

                @Test func codable_Direction() async throws {
                        try await checkCodablePropertyLaws(
                            for: Direction.self,
                            using: Gen<Character>.letterOrNumber.string(of: 0...8)
                                .compactMap { Direction(rawValue: $0) }
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }

    @Test func caseIterableEnumDerivesAllCasesGenerator() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            enum Status: CaseIterable, Equatable {
                case pending, active, archived
            }
            """,
            expandedSource: """
            enum Status: CaseIterable, Equatable {
                case pending, active, archived
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

    @Test func userGenInBodyOverridesDerivation() {
        // Even on a CaseIterable enum, defining `static func gen()` in the
        // type's primary body wins — the user's intent is the highest-
        // priority strategy in PRD §5.7.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            enum Status: CaseIterable, Equatable {
                case pending, active

                static func gen() -> Generator<Status, some SendableSequenceType> {
                    Gen.element(of: Status.allCases)
                }
            }
            """,
            expandedSource: """
            enum Status: CaseIterable, Equatable {
                case pending, active

                static func gen() -> Generator<Status, some SendableSequenceType> {
                    Gen.element(of: Status.allCases)
                }
            }

            struct StatusPropertyLawTests {
                @Test func equatable_Status() async throws {
                        try await checkEquatablePropertyLaws(
                            for: Status.self,
                            using: Status.gen()
                        )
                    }
            }
            """,
            macros: testMacros
        )
    }
}
