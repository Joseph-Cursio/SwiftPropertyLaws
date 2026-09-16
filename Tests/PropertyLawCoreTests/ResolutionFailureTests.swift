import Testing
@testable import PropertyLawCore

/// `GeneratorResolver.resolutionFailure(forTypeName:)` — one answer per `nil`
/// path in the resolver, where a caller used to get only the `nil`.
struct ResolutionFailureTests {

    private func structShape(
        _ name: String,
        _ members: [(String, String)] = [],
        hasUserInit: Bool = false
    ) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members.map { StoredMember(name: $0.0, typeName: $0.1) },
            hasUserInit: hasUserInit
        )
    }

    @Test("a type that resolves has no failure")
    func resolvedTypeHasNoFailure() {
        let resolver = GeneratorResolver(types: [structShape("Point", [("x", "Int")])])
        #expect(resolver.resolutionFailure(forTypeName: "Point") == nil)
    }

    @Test("a name outside the universe is reported as such")
    func notInUniverse() {
        let resolver = GeneratorResolver(types: [structShape("Point", [("x", "Int")])])
        #expect(resolver.resolutionFailure(forTypeName: "Foreign") == .notInUniverse)
    }

    /// The reason the strategist wrote, not a paraphrase of it — the sentence
    /// `derive` used to discard.
    @Test("a .todo carries the strategist's own reason verbatim")
    func noStrategyCarriesReason() {
        let blocked = structShape("Blocked", [("handle", "SomeExternalHandle")])
        let resolver = GeneratorResolver(types: [blocked])
        guard case .todo(let expected) = DerivationStrategist.strategy(
            for: blocked, resolve: resolver.customTypeGenerator
        ) else {
            Issue.record("fixture should not derive")
            return
        }
        #expect(resolver.resolutionFailure(forTypeName: "Blocked") == .noStrategy(reason: expected))
    }

    /// The census case: the owner fails because a member failed, and asking
    /// about the member explains why.
    @Test("a failing member is explained under its own name")
    func nestedFailureIsExplained() {
        let owner = structShape("Owner", [("inner", "Inner")])
        let inner = structShape("Inner", hasUserInit: true)
        let resolver = GeneratorResolver(types: [owner, inner])
        #expect(resolver.customTypeGenerator(forTypeName: "Owner") == nil)
        guard case .noStrategy(let reason) = resolver.resolutionFailure(forTypeName: "Inner") else {
            Issue.record("expected .noStrategy for Inner")
            return
        }
        #expect(reason.contains("Inner"))
    }

    @Test("two distinct types sharing a name are reported ambiguous")
    func ambiguousName() {
        let resolver = GeneratorResolver(types: [
            structShape("Kind", [("a", "Int")]),
            structShape("Kind", [("b", "String")])
        ])
        #expect(resolver.resolutionFailure(forTypeName: "Kind") == .ambiguous)
    }

    @Test("an ambiguous nested leaf is reported ambiguous, not missing")
    func ambiguousLeaf() {
        let resolver = GeneratorResolver(types: [
            structShape("Foo.Kind", [("a", "Int")]),
            structShape("Bar.Kind", [("b", "String")])
        ])
        #expect(resolver.resolutionFailure(forTypeName: "Kind") == .ambiguous)
        #expect(resolver.resolutionFailure(forTypeName: "Foo.Kind") == nil)
    }

    @Test("a leaf reference reports its qualified type's failure")
    func leafSpellingCarriesFailure() {
        let resolver = GeneratorResolver(types: [structShape("Outer.Inner", hasUserInit: true)])
        guard case .noStrategy = resolver.resolutionFailure(forTypeName: "Inner") else {
            Issue.record("expected .noStrategy under the leaf spelling")
            return
        }
    }

    @Test("an alias to an unresolvable type names the underlying spelling")
    func aliasUnresolved() {
        let resolver = GeneratorResolver(types: [], aliases: ["Handle": "OpaquePointer"])
        #expect(
            resolver.resolutionFailure(forTypeName: "Handle")
                == .aliasUnresolved(underlying: "OpaquePointer")
        )
    }

    @Test("a bare self-reference is reported as unterminated recursion")
    func unterminatedRecursion() {
        let resolver = GeneratorResolver(types: [structShape("Node", [("value", "Int"), ("next", "Node")])])
        #expect(resolver.resolutionFailure(forTypeName: "Node") == .unterminatedRecursion)
    }

    /// The failure map is filled as a side effect of resolving, so the query
    /// must resolve on its own rather than read whatever happens to be there.
    @Test("the answer does not depend on what was resolved first")
    func answerIsOrderIndependent() {
        let universe = [structShape("Owner", [("inner", "Inner")]), structShape("Inner", hasUserInit: true)]
        let cold = GeneratorResolver(types: universe)
        let warm = GeneratorResolver(types: universe)
        _ = warm.customTypeGenerator(forTypeName: "Owner")
        #expect(cold.resolutionFailure(forTypeName: "Inner") == warm.resolutionFailure(forTypeName: "Inner"))
        #expect(cold.resolutionFailure(forTypeName: "Inner") != nil)
    }
}
