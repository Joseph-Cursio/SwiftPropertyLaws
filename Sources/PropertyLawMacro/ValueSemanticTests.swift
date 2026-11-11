/// v3.6.0 — peer macro that attaches to a `ValueSemantic` conformer and emits a
/// sibling `<TypeName>ValueSemanticTests` `@Suite` struct with a single
/// `@Test func` calling `checkValueSemanticPropertyLaws(for: Self.self)` — so a
/// type adopting value semantics gets the copy-mutate-compare law (single-step
/// + multi-step interleaving) checked on every CI run. The ValueSemantic analog
/// of `@InteractionInvariantTests`.
///
/// **Required conformance.** The decoratee's primary declaration must list
/// `ValueSemantic` (the macro sees only the decoratee's syntax, not sibling
/// extensions). Unlike the interaction macro, the emit references no
/// `initialState` / `reducer` — the `ValueSemantic` conformance already carries
/// `makeProbe` / `Mutation` / `apply` (+ `Equatable`).
///
/// ```swift
/// @ValueSemanticTests
/// struct Buffer: ValueSemantic {
///     // makeProbe / Mutation / apply / == …
/// }
/// ```
///
/// Expands (as a peer of `Buffer`) to:
/// ```swift
/// struct BufferValueSemanticTests {
///     @Test func valueSemantic_Buffer() async throws {
///         try await checkValueSemanticPropertyLaws(for: Buffer.self)
///     }
/// }
/// ```
@attached(peer, names: suffixed(ValueSemanticTests))
// swiftlint:disable:next unused_declaration - public macro; clients apply it as an attribute
public macro ValueSemanticTests() = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "ValueSemanticTestsMacro"
)
