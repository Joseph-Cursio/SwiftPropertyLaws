/// v3.9.0 — peer macro for a `DefensiveCopy` conformer: emits a sibling
/// `<TypeName>DefensiveCopyTests` `@Suite` whose `@Test` calls
/// `checkDefensiveCopyPropertyLaws(for: Self.self)` (distinctness + independence,
/// Ch. 9 §9.3.2). The decoratee's primary declaration must list `DefensiveCopy`.
///
/// ```swift
/// @DefensiveCopyTests
/// final class Buffer: DefensiveCopy { /* makeProbe / copyUnderTest / Mutation / apply / == */ }
/// ```
@attached(peer, names: suffixed(DefensiveCopyTests))
public macro DefensiveCopyTests() = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "DefensiveCopyTestsMacro"
)
