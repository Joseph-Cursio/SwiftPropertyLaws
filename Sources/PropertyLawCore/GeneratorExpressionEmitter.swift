/// Translates a `DerivationStrategy` to the Swift expression text spelled
/// at each `using:` argument site by every consumer of
/// `DerivationStrategist` — the `@PropertyLawSuite` macro, the
/// `swift package propertylawcheck discover` plugin, and (as of the v1.7
/// K-prep-M1 promotion) any downstream consumer such as
/// SwiftInferProperties M5's lifted-test stub writeout.
///
/// Single source of truth for the strategy → Swift-source mapping.
/// Before this enum landed the macro impl and the discovery tool each
/// carried their own copy of the switch, with one subtle drift between
/// them (the discovery tool emitted `.compactMap` on the same line as
/// the raw-type generator while the macro split them across lines for
/// line-width reasons) — both sites now call the same function and
/// produce byte-identical output.
///
/// Strategy → expression:
///
/// - `.userGen` → `<TypeName>.gen()`.
/// - `.todo` → the same call **plus a trailing marker comment**. It relies on
///   the compile error from a missing `gen()` symbol to surface to the user,
///   with the macro's `noKnownConformance`-class diagnostic for context — but
///   the call alone is indistinguishable from a working `.userGen`, and that
///   ambiguity is not academic: a survey of generated output counted `.userGen`
///   entries as unresolved because both render as `Foo.gen()`. The compiler can
///   tell them apart; a reader, a grep and a reviewer could not. See
///   `todoMarker`.
/// - `.caseIterable` → `Gen<TypeName?>.element(of: TypeName.allCases).compactMap { $0 }`.
/// - `.memberwiseArbitrary(members:)` → delegated to `MemberwiseEmitter`
///   for the `zip(...)` + tuple-positional map shape.
/// - `.rawRepresentable(rawType)` → the raw-type generator + a
///   `.compactMap { TypeName(rawValue: $0) }` lift on its own line so
///   even types with long names + long raw-type generators (e.g.
///   `String`'s `Gen<Character>.letterOrNumber.string(of: 0...8)`) stay
///   within reasonable line widths.
public enum GeneratorExpressionEmitter {

    /// Trailing marker distinguishing a deliberate compile error from a working
    /// user generator.
    ///
    /// **A trailing line comment is safe here and only here.** `.todo` reaches
    /// the emitter from exactly two callers — the discovery plugin's `using:`
    /// argument line and the peer macro's — and both put the expression last on
    /// its line. `GeneratorResolver` and `ScaffoldEmitter`, the two callers that
    /// splice an expression *into* a larger one, both `return nil` on `.todo`
    /// before reaching here, so the comment can never swallow the remainder of a
    /// composed expression. `EmittedFileParsesTests` parses whole emitted files
    /// to keep that true rather than assumed.
    public static let todoMarker =
        "// TODO: no generator derived — supply `static func gen()` (this line will not compile)"

    /// Emit the generator expression for `strategy` against `typeName`.
    /// Output is suitable for direct substitution into a `using:`
    /// argument site or a `Tests/Generated/SwiftInfer/` stub body.
    public static func expression(
        typeName: String,
        strategy: DerivationStrategy
    ) -> String {
        switch strategy {
        case .userGen:
            return "\(typeName).gen()"
        case .todo:
            return "\(typeName).gen()  \(Self.todoMarker)"
        case .caseIterable:
            // `Gen.element(of:)` is declared `where Value == C.Element?`, so it
            // produces a `Generator<T?, _>`. The `Gen<T>` spelling this line
            // carried until now could therefore never compile: *"static method
            // 'element(of:)' requires the types 'T' and 'T?' be equivalent."*
            //
            // The emitted form now matches the spelling every hand-written call
            // site in this repo already used (`CaseIterableLawsTests`,
            // `RawRepresentableLawsTests`, the planted-bug suites): name the
            // Optional explicitly and drop it with `compactMap`. Explicit rather
            // than inferred because this expression is interpolated into
            // *composed* positions — inside a `zip(…).map { … }` for a member —
            // where leaving `Value` to inference is fragile.
            //
            // The expression had never been executed. Every consumer that
            // reached it emitted a stub that failed to build, and a failed build
            // surfaces downstream as an *architectural* non-verdict rather than
            // as a codegen error — so nothing ever pointed at this line, and the
            // unit test below asserted the broken string verbatim. Found by
            // SwiftInferProperties' self-dogfood road test, whose corpus is the
            // first to put a `CaseIterable` enum in a *member* position; see
            // `SwiftInferProperties/docs/measurements/roadtest-self-dogfood.md`
            // §9.2.
            return "Gen<\(typeName)?>.element(of: \(typeName).allCases).compactMap { $0 }"
        case .memberwiseArbitrary(let members):
            return MemberwiseEmitter.expression(typeName: typeName, members: members)
        case .initializerBased(let arguments):
            return MemberwiseEmitter.compose(
                typeName: typeName,
                arguments: arguments.map { (label: $0.label, expression: $0.generatorExpression) }
            )
        case .enumCases(let cases):
            return EnumCaseEmitter.expression(typeName: typeName, cases: cases)
        case .rawRepresentable(let rawType):
            return """
                \(rawType.generatorExpression)
                            .compactMap { \(typeName)(rawValue: $0) }
                """
        }
    }
}
