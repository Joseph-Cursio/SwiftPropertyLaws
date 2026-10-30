import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import Testing
@testable import PropertyLawMacroImpl

/// Single source-of-truth macro registry for `assertMacroExpansion`.
/// `nonisolated(unsafe)` because `assertMacroExpansion` itself isn't
/// actor-isolated; the dictionary is read-only after init.
nonisolated(unsafe) let testMacros: [String: Macro.Type] = [
    "PropertyLawSuite": PropertyLawSuiteMacro.self
]

// One golden-output test per emit-able protocol; the suite legitimately
// grows past SwiftLint's default body-length and file-length thresholds
// as new protocols ship. The disables are paired with an explicit
// re-enable at end of file.
// swiftlint:disable type_body_length file_length

struct MacroExpansionTests {

    /// The warning for a type whose only initializers are ones derivation
    /// declines, such as a failable `init?(rawValue:)`.
    private static func noUsableInitializer(_ typeName: String) -> DiagnosticSpec {
        DiagnosticSpec(
            message: """
                Cannot derive a generator for `\(typeName)`: the type's user \
                `init(...)` declarations don't support derivation — each is \
                failable, throwing, access-restricted, parameterless, over 100 \
                parameters, or unsafe to call with independently drawn \
                arguments (a capacity hint, a private-storage label, or a \
                stated precondition). Provide `static func gen() -> \
                Generator<\(typeName), some SendableSequenceType>`.
                """,
            line: 1,
            column: 1,
            severity: .warning
        )
    }

    @Test func equatableConformancesEmitsPeerSuite() {
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

    @Test func hashableSubsumesEquatable() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo: Equatable, Hashable {
                let value: Int
            }
            """,
            expandedSource: """
            struct Foo: Equatable, Hashable {
                let value: Int
            }

            struct FooPropertyLawTests {
                @Test func hashable_Foo() async throws {
                    try await checkHashablePropertyLaws(
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

    @Test func comparableSubsumesEquatable() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo: Comparable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
            }
            """,
            expandedSource: """
            struct Foo: Comparable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
            }

            struct FooPropertyLawTests {
                @Test func comparable_Foo() async throws {
                    try await checkComparablePropertyLaws(
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

    @Test func identifiableEmitsIdStabilityCheck() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct User: Identifiable {
                let id: Int
                let name: String
            }
            """,
            expandedSource: """
            struct User: Identifiable {
                let id: Int
                let name: String
            }

            struct UserPropertyLawTests {
                @Test func identifiable_User() async throws {
                    try await checkIdentifiablePropertyLaws(
                        for: User.self,
                        using: zip(Gen<Int>.int(), Gen<Character>.letterOrNumber.string(of: 0 ... 8))
                        .map {
                            User(id: $0.0, name: $0.1)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func losslessStringConvertibleEmitsRoundTripCheck() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Slug: LosslessStringConvertible, Equatable {
                let value: String
                init?(_ description: String) { self.value = description }
                var description: String { value }
            }
            """,
            expandedSource: """
            struct Slug: LosslessStringConvertible, Equatable {
                let value: String
                init?(_ description: String) { self.value = description }
                var description: String { value }
            }

            struct SlugPropertyLawTests {
                @Test func equatable_Slug() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Slug.self,
                        using: Slug.gen()  // TODO: no generator derived — supply `static func gen()` \
            (this line will not compile)
                    )
                }

                @Test func losslessStringConvertible_Slug() async throws {
                    try await checkLosslessStringConvertiblePropertyLaws(
                        for: Slug.self,
                        using: Slug.gen()  // TODO: no generator derived — supply `static func gen()` \
            (this line will not compile)
                    )
                }
            }
            """,
            diagnostics: [Self.noUsableInitializer("Slug")],
            macros: testMacros
        )
    }

    @Test func rawRepresentableEmitsRoundTripCheck() {
        // Explicit `: RawRepresentable` in the inheritance clause emits
        // `checkRawRepresentablePropertyLaws`. Raw-value enums that
        // synthesize the conformance via `: String` / `: Int` etc. don't
        // match this detection — the macro only sees inheritance clauses
        // syntactically.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Token: RawRepresentable, Equatable {
                let rawValue: String
                init?(rawValue: String) { self.rawValue = rawValue }
            }
            """,
            expandedSource: """
            struct Token: RawRepresentable, Equatable {
                let rawValue: String
                init?(rawValue: String) { self.rawValue = rawValue }
            }

            struct TokenPropertyLawTests {
                @Test func equatable_Token() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Token.self,
                        using: Token.gen()  // TODO: no generator derived — supply `static func gen()` \
            (this line will not compile)
                    )
                }

                @Test func rawRepresentable_Token() async throws {
                    try await checkRawRepresentablePropertyLaws(
                        for: Token.self,
                        using: Token.gen()  // TODO: no generator derived — supply `static func gen()` \
            (this line will not compile)
                    )
                }
            }
            """,
            diagnostics: [Self.noUsableInitializer("Token")],
            macros: testMacros
        )
    }

    @Test func strideableSubsumesEmitsComparable() {
        // `Strideable` itself is unemittable — its check function takes a
        // `strideGenerator:` arg the macro can't synthesize from syntax alone.
        // But `Strideable` refines `Comparable` in stdlib, so `set(from:)`
        // auto-adds Comparable, and the macro emits `checkComparablePropertyLaws`
        // (which runs Equatable's laws first via inheritance at runtime).
        // Strideable's own laws stay a manual call.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Foo: Strideable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
                func distance(to other: Foo) -> Int { other.value - value }
                func advanced(by step: Int) -> Foo { Foo(value: value + step) }
            }
            """,
            expandedSource: """
            struct Foo: Strideable {
                let value: Int
                static func < (lhs: Foo, rhs: Foo) -> Bool { lhs.value < rhs.value }
                func distance(to other: Foo) -> Int { other.value - value }
                func advanced(by step: Int) -> Foo { Foo(value: value + step) }
            }

            struct FooPropertyLawTests {
                @Test func comparable_Foo() async throws {
                    try await checkComparablePropertyLaws(
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

    @Test func codableEmitsBothEquatableAndCodable() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Record: Codable, Equatable {
                let id: Int
            }
            """,
            expandedSource: """
            struct Record: Codable, Equatable {
                let id: Int
            }

            struct RecordPropertyLawTests {
                @Test func equatable_Record() async throws {
                    try await checkEquatablePropertyLaws(
                        for: Record.self,
                        using: Gen<Int>.int().map {
                            Record(id: $0)
                        }
                    )
                }

                @Test func codable_Record() async throws {
                    try await checkCodablePropertyLaws(
                        for: Record.self,
                        using: Gen<Int>.int().map {
                            Record(id: $0)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func collectionSubsumesSequenceAndIterator() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Pages: Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                subscript(position: Int) -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Pages: Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                subscript(position: Int) -> Int { 0 }
            }

            struct PagesPropertyLawTests {
                @Test func collection_Pages() async throws {
                    try await checkCollectionPropertyLaws(
                        for: Pages.self,
                        using: Gen.always(Pages())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func randomAccessCollectionSubsumesBidirectionalAndCollection() {
        // RandomAccessCollection's subsumed set is transitive — a single
        // checkRandomAccessCollectionPropertyLaws call runs the inherited
        // BidirectionalCollection / Collection / Sequence / Iterator laws.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Pages: RandomAccessCollection, BidirectionalCollection, Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { 0 }
            }
            """,
            expandedSource: """
            struct Pages: RandomAccessCollection, BidirectionalCollection, Collection {
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { 0 }
            }

            struct PagesPropertyLawTests {
                @Test func randomAccessCollection_Pages() async throws {
                    try await checkRandomAccessCollectionPropertyLaws(
                        for: Pages.self,
                        using: Gen.always(Pages())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func signedNumericSubsumesNumericAndAdditiveArithmetic() {
        // The algebraic chain refines AdditiveArithmetic ← Numeric ← SignedNumeric.
        // A type spelled `: SignedNumeric` should emit only the SignedNumeric
        // call; the inherited suites run at runtime via .all dispatch.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Quaternion: SignedNumeric {
                init(integerLiteral value: Int) {}
                init?(exactly source: some BinaryInteger) {}
                var magnitude: Int { 0 }
                static var zero: Quaternion { Quaternion(integerLiteral: 0) }
                static func + (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func - (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func * (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func *= (a: inout Quaternion, b: Quaternion) {}
            }
            """,
            expandedSource: """
            struct Quaternion: SignedNumeric {
                init(integerLiteral value: Int) {}
                init?(exactly source: some BinaryInteger) {}
                var magnitude: Int { 0 }
                static var zero: Quaternion { Quaternion(integerLiteral: 0) }
                static func + (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func - (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func * (a: Quaternion, b: Quaternion) -> Quaternion { a }
                static func *= (a: inout Quaternion, b: Quaternion) {}
            }

            struct QuaternionPropertyLawTests {
                @Test func signedNumeric_Quaternion() async throws {
                    try await checkSignedNumericPropertyLaws(
                        for: Quaternion.self,
                        using: Gen<Int>.int().map {
                            Quaternion(integerLiteral: $0)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func signedIntegerCollapsesDiamondToSingleEmission() {
        // SignedInteger refines BOTH BinaryInteger and SignedNumeric in stdlib.
        // The diamond should collapse under mostSpecific to a single
        // `checkSignedIntegerPropertyLaws` call; runtime dispatch through
        // .all then runs both inherited suites.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct WideInt: SignedInteger {}
            """,
            expandedSource: """
            struct WideInt: SignedInteger {}

            struct WideIntPropertyLawTests {
                @Test func signedInteger_WideInt() async throws {
                    try await checkSignedIntegerPropertyLaws(
                        for: WideInt.self,
                        using: Gen.always(WideInt())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func stringProtocolSubsumesBidirectionalCollectionChain() {
        // StringProtocol refines BidirectionalCollection (and transitively
        // Collection / Sequence / IteratorProtocol). Most-specific dedupe
        // collapses the chain to a single `checkStringProtocolPropertyLaws` call.
        // Hashable / Comparable / LosslessStringConvertible stay
        // unsubsumed — they test different invariants.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct CharBuffer: StringProtocol {}
            """,
            expandedSource: """
            struct CharBuffer: StringProtocol {}

            struct CharBufferPropertyLawTests {
                @Test func stringProtocol_CharBuffer() async throws {
                    try await checkStringProtocolPropertyLaws(
                        for: CharBuffer.self,
                        using: Gen.always(CharBuffer())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func binaryFloatingPointSubsumesFloatingPoint() {
        // BinaryFloatingPoint subsumes FloatingPoint and (transitively)
        // the algebraic chain. A type spelled `: BinaryFloatingPoint`
        // emits only the BinaryFloatingPoint check.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Quad: BinaryFloatingPoint {}
            """,
            expandedSource: """
            struct Quad: BinaryFloatingPoint {}

            struct QuadPropertyLawTests {
                @Test func binaryFloatingPoint_Quad() async throws {
                    try await checkBinaryFloatingPointPropertyLaws(
                        for: Quad.self,
                        using: Gen.always(Quad())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func floatingPointSubsumesAlgebraicChain() {
        // FloatingPoint subsumes SignedNumeric → Numeric → AdditiveArithmetic
        // because exact-equality algebraic laws don't hold on IEEE-754. A
        // type spelled `: FloatingPoint` emits only the FloatingPoint check.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Quad: FloatingPoint {}
            """,
            expandedSource: """
            struct Quad: FloatingPoint {}

            struct QuadPropertyLawTests {
                @Test func floatingPoint_Quad() async throws {
                    try await checkFloatingPointPropertyLaws(
                        for: Quad.self,
                        using: Gen.always(Quad())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func fixedWidthAndSignedIntegerSurviveAsSiblings() {
        // FixedWidthInteger and SignedInteger are independent siblings —
        // FixedWidthInteger refines BinaryInteger, SignedInteger refines
        // BinaryInteger and SignedNumeric, neither subsumes the other.
        // Both checks should emit (matches the v1.2 Mutable+Bidirectional
        // sibling pattern).
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Word: FixedWidthInteger, SignedInteger {}
            """,
            expandedSource: """
            struct Word: FixedWidthInteger, SignedInteger {}

            struct WordPropertyLawTests {
                @Test func signedInteger_Word() async throws {
                    try await checkSignedIntegerPropertyLaws(
                        for: Word.self,
                        using: Gen.always(Word())
                    )
                }

                @Test func fixedWidthInteger_Word() async throws {
                    try await checkFixedWidthIntegerPropertyLaws(
                        for: Word.self,
                        using: Gen.always(Word())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func unsignedIntegerCollapsesToSingleEmission() {
        // UnsignedInteger subsumes BinaryInteger → Numeric → AdditiveArithmetic.
        // Single emission expected.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct BigUInt: UnsignedInteger {}
            """,
            expandedSource: """
            struct BigUInt: UnsignedInteger {}

            struct BigUIntPropertyLawTests {
                @Test func unsignedInteger_BigUInt() async throws {
                    try await checkUnsignedIntegerPropertyLaws(
                        for: BigUInt.self,
                        using: Gen.always(BigUInt())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func mutableAndRangeReplaceableSurviveAsSiblings() {
        // MutableCollection and RangeReplaceableCollection are independent
        // refinements of Collection — neither subsumes the other, so both
        // emit alongside RandomAccessCollection.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Buffer: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
                init() {}
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { get { 0 } set {} }
                mutating func replaceSubrange<C: Collection>(_ s: Range<Int>, with c: C) where C.Element == Int {}
            }
            """,
            expandedSource: """
            struct Buffer: RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
                init() {}
                var startIndex: Int { 0 }
                var endIndex: Int { 0 }
                func index(after i: Int) -> Int { i + 1 }
                func index(before i: Int) -> Int { i - 1 }
                subscript(position: Int) -> Int { get { 0 } set {} }
                mutating func replaceSubrange<C: Collection>(_ s: Range<Int>, with c: C) where C.Element == Int {}
            }

            struct BufferPropertyLawTests {
                @Test func randomAccessCollection_Buffer() async throws {
                    try await checkRandomAccessCollectionPropertyLaws(
                        for: Buffer.self,
                        using: Gen.always(Buffer())
                    )
                }

                @Test func mutableCollection_Buffer() async throws {
                    try await checkMutableCollectionPropertyLaws(
                        for: Buffer.self,
                        using: Gen.always(Buffer())
                    )
                }

                @Test func rangeReplaceableCollection_Buffer() async throws {
                    try await checkRangeReplaceableCollectionPropertyLaws(
                        for: Buffer.self,
                        using: Gen.always(Buffer())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - v1.8 kit-defined algebraic protocols

    @Test func semigroupConformanceEmitsPeerSuite() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Counter: Semigroup {
                let value: Int
            }
            """,
            expandedSource: """
            struct Counter: Semigroup {
                let value: Int
            }

            struct CounterPropertyLawTests {
                @Test func semigroup_Counter() async throws {
                    try await checkSemigroupPropertyLaws(
                        for: Counter.self,
                        using: Gen<Int>.int().map {
                            Counter(value: $0)
                        }
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func monoidSubsumesSemigroup() {
        // Monoid refines kit-defined Semigroup. A type spelled
        // `: Semigroup, Monoid` should emit only the Monoid call —
        // checkMonoidPropertyLaws auto-runs Semigroup's law via .all.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Tally: Semigroup, Monoid {}
            """,
            expandedSource: """
            struct Tally: Semigroup, Monoid {}

            struct TallyPropertyLawTests {
                @Test func monoid_Tally() async throws {
                    try await checkMonoidPropertyLaws(
                        for: Tally.self,
                        using: Gen.always(Tally())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func bareMonoidConformanceEmitsMonoidCall() {
        // A type spelled `: Monoid` alone (Semigroup implied by refinement)
        // emits the Monoid check with no Semigroup duplicate.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Tally: Monoid {}
            """,
            expandedSource: """
            struct Tally: Monoid {}

            struct TallyPropertyLawTests {
                @Test func monoid_Tally() async throws {
                    try await checkMonoidPropertyLaws(
                        for: Tally.self,
                        using: Gen.always(Tally())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    // MARK: - v1.9 kit-defined CommutativeMonoid / Group / Semilattice

    @Test func commutativeMonoidSubsumesMonoidAndSemigroup() {
        // CommutativeMonoid refines Monoid (and transitively Semigroup).
        // A type spelled `: Semigroup, Monoid, CommutativeMonoid` emits
        // only the CommutativeMonoid call.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Tally: Semigroup, Monoid, CommutativeMonoid {}
            """,
            expandedSource: """
            struct Tally: Semigroup, Monoid, CommutativeMonoid {}

            struct TallyPropertyLawTests {
                @Test func commutativeMonoid_Tally() async throws {
                    try await checkCommutativeMonoidPropertyLaws(
                        for: Tally.self,
                        using: Gen.always(Tally())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func bareCommutativeMonoidConformanceEmitsCMonCall() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct Tally: CommutativeMonoid {}
            """,
            expandedSource: """
            struct Tally: CommutativeMonoid {}

            struct TallyPropertyLawTests {
                @Test func commutativeMonoid_Tally() async throws {
                    try await checkCommutativeMonoidPropertyLaws(
                        for: Tally.self,
                        using: Gen.always(Tally())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func groupSubsumesMonoidAndSemigroup() {
        // Group refines Monoid; non-commutative groups are valid so Group
        // does NOT subsume CommutativeMonoid. A type spelled
        // `: Monoid, Group` emits only the Group call.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct AdditiveInt: Monoid, Group {}
            """,
            expandedSource: """
            struct AdditiveInt: Monoid, Group {}

            struct AdditiveIntPropertyLawTests {
                @Test func group_AdditiveInt() async throws {
                    try await checkGroupPropertyLaws(
                        for: AdditiveInt.self,
                        using: Gen.always(AdditiveInt())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func commutativeMonoidAndGroupAreIncomparable() {
        // CommutativeMonoid and Group are incomparable arms in the
        // protocol DAG (kit-side CommutativeGroup is out of v1.9 scope).
        // A type spelled `: CommutativeMonoid, Group` emits BOTH calls.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct AdditiveInt: CommutativeMonoid, Group {}
            """,
            expandedSource: """
            struct AdditiveInt: CommutativeMonoid, Group {}

            struct AdditiveIntPropertyLawTests {
                @Test func commutativeMonoid_AdditiveInt() async throws {
                    try await checkCommutativeMonoidPropertyLaws(
                        for: AdditiveInt.self,
                        using: Gen.always(AdditiveInt())
                    )
                }

                @Test func group_AdditiveInt() async throws {
                    try await checkGroupPropertyLaws(
                        for: AdditiveInt.self,
                        using: Gen.always(AdditiveInt())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func semilatticeSubsumesCommutativeMonoidChain() {
        // Semilattice refines CommutativeMonoid (and transitively Monoid +
        // Semigroup). A type spelled with the full chain emits only the
        // Semilattice call.
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct MaxInt: Semigroup, Monoid, CommutativeMonoid, Semilattice {}
            """,
            expandedSource: """
            struct MaxInt: Semigroup, Monoid, CommutativeMonoid, Semilattice {}

            struct MaxIntPropertyLawTests {
                @Test func semilattice_MaxInt() async throws {
                    try await checkSemilatticePropertyLaws(
                        for: MaxInt.self,
                        using: Gen.always(MaxInt())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }

    @Test func bareSemilatticeConformanceEmitsSemilatticeCall() {
        assertMacroExpansion(
            """
            @PropertyLawSuite
            struct MaxInt: Semilattice {}
            """,
            expandedSource: """
            struct MaxInt: Semilattice {}

            struct MaxIntPropertyLawTests {
                @Test func semilattice_MaxInt() async throws {
                    try await checkSemilatticePropertyLaws(
                        for: MaxInt.self,
                        using: Gen.always(MaxInt())
                    )
                }
            }
            """,
            macros: testMacros
        )
    }
}

// swiftlint:enable type_body_length file_length
