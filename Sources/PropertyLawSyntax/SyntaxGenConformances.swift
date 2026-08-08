import PropertyBased
import SwiftSyntax

/// `static func gen()` on the swift-syntax node types.
///
/// **This is what closes the loop with the discovery plugin, and it needs no
/// emitter change at all.** `GeneratorExpressionEmitter` renders a `.todo`
/// strategy as `"\(typeName).gen()"` — the same spelling PRD §5.7's Strategy A
/// (user-provided `gen()`) uses. So a generated suite that today reads
///
/// ```swift
/// try await checkHashablePropertyLaws(for: Syntax.self, using: Syntax.gen())
/// ```
///
/// is *already the right code*; it only lacked the method. Declaring it here
/// makes 303 `Syntax` slots and 34 `ExprSyntax` slots compile as written.
///
/// **Why extensions rather than entries in the kit's known-generator table.**
/// `CompositeMemberParser.knownValueGenerator` is how `UUID` and `Date` resolve,
/// and adding `Syntax` there would work — but it would also make the emitter
/// write `import PropertyLawSyntax` into generated files. Foundation is always
/// available; this product is opt-in, so that import would break the build of
/// every project that has a `Syntax`-typed member and no dependency on it,
/// turning a clear "provide a gen()" diagnostic into an obscure "no such
/// module". Shipping the method instead means a project that *has* the product
/// gets working code and a project that doesn't sees no change.
///
/// The one thing this does not solve: the generated file still needs
/// `import PropertyLawSyntax`, and the emitter has no per-type module
/// provenance to know that. Same open question as the foreign-type import gap.
public extension Syntax {
    /// See `Gen<Syntax>.syntax()` for why this parses a fresh tree per draw
    /// rather than drawing from a pool.
    static func gen() -> Generator<Syntax, some SendableSequenceType> {
        Gen<Syntax>.syntax()
    }
}

public extension ExprSyntax {
    static func gen() -> Generator<ExprSyntax, some SendableSequenceType> {
        Gen<ExprSyntax>.syntaxNode()
    }
}

public extension DeclSyntax {
    static func gen() -> Generator<DeclSyntax, some SendableSequenceType> {
        Gen<DeclSyntax>.syntaxNode()
    }
}

public extension StmtSyntax {
    static func gen() -> Generator<StmtSyntax, some SendableSequenceType> {
        Gen<StmtSyntax>.syntaxNode()
    }
}

public extension PatternSyntax {
    static func gen() -> Generator<PatternSyntax, some SendableSequenceType> {
        Gen<PatternSyntax>.syntaxNode()
    }
}

public extension TypeSyntax {
    static func gen() -> Generator<TypeSyntax, some SendableSequenceType> {
        Gen<TypeSyntax>.syntaxNode()
    }
}

public extension TokenSyntax {
    static func gen() -> Generator<TokenSyntax, some SendableSequenceType> {
        Gen<TokenSyntax>.syntaxNode()
    }
}
