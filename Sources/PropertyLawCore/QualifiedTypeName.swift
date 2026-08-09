/// A scanned type name is used in two incompatible positions, and once the
/// scanner started recording nested types by qualified name the two had to stop
/// being the same string.
///
/// - **Type position** — `for: BitSet.Counted.self`, `BitSet.Counted(a: …)`.
///   Needs the qualified spelling; the bare leaf does not resolve at module
///   scope. Every emitter interpolates the name verbatim here, which is why
///   `GeneratorResolver`'s header calls qualified names "the escape hatch [that]
///   needs no emitter support".
/// - **Identifier position** — `@Suite struct <X>PropertyLawTests`,
///   `@Test func hashable_<X>`, and the `// property-law-suppress: <key>`
///   marker. A dot is not legal in a Swift identifier, so the qualified
///   spelling produces `@Suite struct BitSet.CountedPropertyLawTests`, which
///   does not parse.
///
/// This is the single place that converts one to the other, so the suite name,
/// the test name and the suppression key can never disagree about what a nested
/// type is called.
public enum QualifiedTypeName {

    /// The identifier-safe form: `BitSet.Counted` → `BitSet_Counted`.
    ///
    /// **Unqualified names pass through untouched**, which is what keeps
    /// existing generated files stable — a `// property-law-suppress:
    /// hashable_Foo` marker written before nested scanning still matches, so
    /// the PRD §5.3 regeneration-as-diff guarantee survives the change.
    ///
    /// Non-identifier characters other than the dot are mapped too, rather than
    /// trusted not to appear. The scanner only produces dotted paths today, but
    /// an identifier that fails to compile is a poor failure mode for a name it
    /// merely passed through.
    public static func identifier(for typeName: String) -> String {
        var out = ""
        out.reserveCapacity(typeName.count)
        for character in typeName {
            out.append(isIdentifierSafe(character) ? character : "_")
        }
        return out
    }

    private static func isIdentifierSafe(_ character: Character) -> Bool {
        character == "_" || character.isLetter || character.isNumber
    }
}
