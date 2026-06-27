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
/// - `.userGen` / `.todo` → `<TypeName>.gen()` (the `.todo` case relies
///   on the compile error from a missing `gen()` symbol to surface to
///   the user, with the macro's `noKnownConformance`-class diagnostic
///   for context).
/// - `.caseIterable` → `Gen<TypeName>.element(of: TypeName.allCases)`.
/// - `.memberwiseArbitrary(members:)` → delegated to `MemberwiseEmitter`
///   for the `zip(...)` + tuple-positional map shape.
/// - `.rawRepresentable(rawType)` → the raw-type generator + a
///   `.compactMap { TypeName(rawValue: $0) }` lift on its own line so
///   even types with long names + long raw-type generators (e.g.
///   `String`'s `Gen<Character>.letterOrNumber.string(of: 0...8)`) stay
///   within reasonable line widths.
public enum GeneratorExpressionEmitter {

    /// Emit the generator expression for `strategy` against `typeName`.
    /// Output is suitable for direct substitution into a `using:`
    /// argument site or a `Tests/Generated/SwiftInfer/` stub body.
    public static func expression(
        typeName: String,
        strategy: DerivationStrategy
    ) -> String {
        switch strategy {
        case .userGen, .todo:
            return "\(typeName).gen()"
        case .caseIterable:
            return "Gen<\(typeName)>.element(of: \(typeName).allCases)"
        case .memberwiseArbitrary(let members):
            return MemberwiseEmitter.expression(typeName: typeName, members: members)
        case .initializerBased(let arguments):
            return MemberwiseEmitter.compose(
                typeName: typeName,
                arguments: arguments.map { (label: $0.label, expression: $0.generatorExpression) }
            )
        case .rawRepresentable(let rawType):
            return """
                \(rawType.generatorExpression)
                            .compactMap { \(typeName)(rawValue: $0) }
                """
        }
    }
}
