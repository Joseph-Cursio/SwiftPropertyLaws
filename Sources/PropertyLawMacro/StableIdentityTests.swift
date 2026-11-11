/// v3.9.0 — peer macro for a `StableIdentity` conformer: emits a sibling
/// `<TypeName>StableIdentityTests` `@Suite` whose `@Test` calls
/// `checkStableIdentityPropertyLaws(for: Self.self)` (hash / equality invariant
/// under mutation, Ch. 9 §9.3.3). The decoratee's primary declaration must list
/// `StableIdentity`.
///
/// ```swift
/// @StableIdentityTests
/// final class Node: StableIdentity { /* makeProbe / Mutation / apply / Hashable */ }
/// ```
@attached(peer, names: suffixed(StableIdentityTests))
public macro StableIdentityTests() = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "StableIdentityTestsMacro"
)
