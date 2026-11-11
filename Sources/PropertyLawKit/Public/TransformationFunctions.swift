/// Caller-supplied element functions for the parameterized transformation
/// laws. The kit cannot invent functions over a generic `Element`, so —
/// like `Strideable`'s `strideGenerator:` — the caller names them
/// explicitly: two endomorphisms (`first`, `second`) and a `predicate`.
///
/// Pick functions that actually *move* elements (`{ $0 &* 2 }`, not
/// `{ $0 }`) and a predicate that splits the generated domain; identity
/// functions and constant predicates satisfy the laws vacuously.
public struct TransformationFunctions<Element: Sendable>: Sendable {
    public let first: @Sendable (Element) -> Element
    public let second: @Sendable (Element) -> Element
    public let predicate: @Sendable (Element) -> Bool

    public init(
        first: @escaping @Sendable (Element) -> Element,
        second: @escaping @Sendable (Element) -> Element,
        predicate: @escaping @Sendable (Element) -> Bool
    ) {
        self.first = first
        self.second = second
        self.predicate = predicate
    }
}
