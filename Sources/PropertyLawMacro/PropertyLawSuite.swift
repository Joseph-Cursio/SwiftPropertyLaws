/// Peer macro that attaches to a type declaration, reads its inheritance
/// clause, and emits a sibling `@Suite` struct of `@Test func` methods —
/// one per recognized stdlib protocol the type conforms to (PRD §4.3).
///
/// The peer-macro shape is required by Swift's macro model: macro
/// implementations see only the syntax of their decoratee, not the
/// surrounding file. PRD §9 Decision 4 already separates whole-module
/// discovery into the upcoming Swift Package Plugin (M2). The PRD's
/// `[Foo.self, Bar.self]`-on-a-test-suite form can't be implemented as
/// a macro for that same reason; it lives on the plugin side.
///
/// Generator-name convention: the macro emits `\(TypeName).gen()` —
/// users define a static `gen()` method on the type (or via an extension
/// in the same module). A missing generator surfaces as a "cannot find
/// `Foo.gen`" compile error, matching PRD §5.7's "compile error beats
/// silent fallthrough" stance. Real generator derivation lands in M3.
///
/// ```swift
/// @PropertyLawSuite
/// struct Foo: Equatable, Hashable {
///     let value: Int
/// }
///
/// extension Foo {
///     static func gen() -> Generator<Foo, some SendableSequenceType> {
///         // ...
///     }
/// }
/// ```
///
/// Expands (as a peer of `Foo`) to:
/// ```swift
/// @Suite struct FooPropertyLawTests {
///     @Test func hashable_Foo() async throws {
///         try await checkHashablePropertyLaws(for: Foo.self, using: Foo.gen())
///     }
/// }
/// ```
@attached(peer, names: suffixed(PropertyLawTests))
public macro PropertyLawSuite() = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "PropertyLawSuiteMacro"
)
