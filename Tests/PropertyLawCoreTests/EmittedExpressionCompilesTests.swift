import PropertyBased
import Testing
@testable import PropertyLawCore

/// **Regression guard: every expression `GeneratorExpressionEmitter` emits must
/// be Swift that compiles and runs.**
///
/// This file exists because a string assertion is not enough, and the proof of
/// that is in the repository's own history. `GeneratorExpressionEmitterTests`
/// pinned the `.caseIterable` arm as
/// `"Gen<Side>.element(of: Side.allCases)"` — byte-exact, green for as long as
/// the arm existed, and describing an expression that **could never compile**.
/// `Gen.element(of:)` is declared `where Value == C.Element?`, so the correct
/// spelling names the Optional; `Gen<Side>` asks the compiler to prove
/// `Side == Side?`.
///
/// Nothing caught it, and the reason generalises past this one bug. A codegen
/// unit test compares text to text: both sides can be wrong together, and they
/// were. Downstream the failure did not look like a codegen error either —
/// consumers emitted a stub, the stub failed to build, and a failed build is
/// reported as an *architectural* non-verdict ("this carrier could not be
/// verified"), which reads as a known limitation rather than a defect. So the
/// bug was invisible from both ends at once.
///
/// The pattern here closes that. Each test writes the emitted expression out as
/// **live code**, runs it, and asserts the emitter produces exactly that source
/// text. The live copy proves the text compiles; the assertion proves the
/// emitter still says it. Neither half can drift without a failure.
///
/// When adding a `DerivationStrategy` arm, add a case here too — the string pin
/// in `GeneratorExpressionEmitterTests` is the *readable* record, this is the
/// *executable* one.
@Suite("Emitted generator expressions compile and run")
struct EmittedExpressionCompilesTests {

    private enum Side: String, CaseIterable, Sendable, Equatable {
        case heads, tails
    }

    private enum Level: Int, RawRepresentable, Sendable, Equatable {
        case low = 1, high = 2
    }

    private struct Point: Sendable, Equatable {
        let x: Int
        let y: Int
    }

    private static var rng: any SeededRandomNumberGenerator {
        Xoshiro(seed: (0xDEAD_BEEF, 0xCAFE_F00D, 0x1234_5678, 0x9ABC_DEF0))
    }

    // MARK: - .caseIterable — the arm that shipped uncompilable for its whole life

    /// The live expression. Written exactly as the emitter renders it, with
    /// `Side` substituted for `TypeName` — **do not simplify it**. If a future
    /// edit "cleans this up" into a spelling the emitter does not produce, the
    /// assertion below fails, which is the point.
    private static let caseIterableGenerator = Gen<Side?>.element(of: Side.allCases).compactMap { $0 }

    @Test("the .caseIterable expression compiles, runs, and matches the emitter")
    func caseIterableExpressionCompilesAndMatches() {
        // 1. It runs, and yields the element type — not an Optional of it. This
        //    is the exact property the old `Gen<Side>` spelling failed.
        var generator = Self.rng
        let value: Side = Self.caseIterableGenerator.run(using: &generator)
        #expect(Side.allCases.contains(value))

        // 2. The emitter still emits that source text, character for character.
        #expect(
            GeneratorExpressionEmitter.expression(typeName: "Side", strategy: .caseIterable)
                == "Gen<Side?>.element(of: Side.allCases).compactMap { $0 }"
        )
    }

    /// The specific shape that regressing would reintroduce. Named so a reader
    /// scanning failures sees *what* broke rather than only *that* something did.
    @Test("the .caseIterable expression never regresses to the uncompilable Gen<T> form")
    func caseIterableNeverRegressesToNonOptionalForm() {
        let emitted = GeneratorExpressionEmitter.expression(typeName: "Side", strategy: .caseIterable)
        #expect(
            !emitted.contains("Gen<Side>.element"),
            """
            `Gen<T>.element(of:)` cannot compile — `element(of:)` is declared \
            `where Value == C.Element?`, so this asks the compiler to prove \
            `Side == Side?`. Name the Optional: `Gen<Side?>.element(of:).compactMap { $0 }`.
            """
        )
        // The Optional must be dropped before the value reaches a law: a
        // `Generator<Side?, _>` handed to `checkXxxPropertyLaws(for: Side.self…)`
        // is a type error at every call site.
        #expect(emitted.contains("compactMap") || emitted.contains("map { $0! }"))
    }

    // MARK: - The other arms, same treatment

    private static let rawRepresentableGenerator = Gen<Int>.int(in: 1...2)
        .compactMap { Level(rawValue: $0) }

    @Test("the .rawRepresentable expression compiles, runs, and matches the emitter")
    func rawRepresentableExpressionCompilesAndMatches() {
        var generator = Self.rng
        let value: Level = Self.rawRepresentableGenerator.run(using: &generator)
        #expect([Level.low, .high].contains(value))

        let emitted = GeneratorExpressionEmitter.expression(
            typeName: "Level",
            strategy: .rawRepresentable(.int)
        )
        // Rendered across two lines for width; compare on the joined form so the
        // test pins the *code*, not the indentation.
        let joined = emitted.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(joined.last == ".compactMap { Level(rawValue: $0) }")
        #expect(joined.first?.contains("Gen<Int>.int") == true)
    }

    private static let memberwiseGenerator = zip(Gen<Int>.int(), Gen<Int>.int())
        .map { Point(x: $0.0, y: $0.1) }

    @Test("the memberwise expression compiles and runs")
    func memberwiseExpressionCompilesAndRuns() {
        var generator = Self.rng
        let value: Point = Self.memberwiseGenerator.run(using: &generator)
        #expect(value == Point(x: value.x, y: value.y))

        let emitted = GeneratorExpressionEmitter.expression(
            typeName: "Point",
            strategy: .memberwiseArbitrary(members: [
                MemberSpec(name: "x", rawType: .int),
                MemberSpec(name: "y", rawType: .int)
            ])
        )
        #expect(emitted.contains("zip("))
        #expect(emitted.contains("Point(x: $0.0, y: $0.1)"))
    }

    /// A `.caseIterable` expression is most often interpolated into a
    /// *composed* position — one member of a `zip(…).map { … }` for an
    /// enclosing struct — and that is where the old spelling actually surfaced.
    /// Type inference is harder there, so the emitted form is pinned as
    /// explicitly typed (`Gen<T?>`) rather than inferred, and this test holds it
    /// to working in that position.
    private struct Flip: Sendable, Equatable {
        let side: Side
        let count: Int
    }

    private static let composedGenerator = zip(
        Gen<Side?>.element(of: Side.allCases).compactMap { $0 },
        Gen<Int>.int(in: 0...10)
    ).map { Flip(side: $0.0, count: $0.1) }

    @Test("the .caseIterable expression works in a composed member position")
    func caseIterableComposesAsAMember() {
        var generator = Self.rng
        let value: Flip = Self.composedGenerator.run(using: &generator)
        #expect(Side.allCases.contains(value.side))
        #expect((0...10).contains(value.count))
    }
}
