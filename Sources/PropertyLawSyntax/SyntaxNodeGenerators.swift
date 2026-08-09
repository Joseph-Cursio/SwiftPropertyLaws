import Foundation
import PropertyBased
import SwiftParser
import SwiftSyntax

/// Generators for the *typed* node types — `ExprSyntax`, `TokenSyntax`,
/// `DeclSyntax` and the rest of swift-syntax's ~300 node structs.
///
/// **Generic rather than three bespoke functions.** `Gen<Syntax>.syntax()`
/// already parses a fresh tree per draw; every other node type is that same
/// tree filtered by `Syntax.as(T.self)`. Writing `ExprSyntax` and `TokenSyntax`
/// by hand would have left `FunctionDeclSyntax`, `ArrayExprSyntax` and every
/// other node the discovery plugin finds still asking for a generator, for no
/// saving.
///
/// **The same identity-equality constraint applies**, and for the same reason
/// the resolution is the same: a fresh tree per draw, so
/// `Hashable.distribution` stays healthy at any budget. See
/// `Gen<Syntax>.syntax()` for the measurement that settled it.
///
/// **`RawTokenSyntax` is deliberately absent.** It is `@_spi(RawSyntax)` —
/// swift-syntax's explicitly unstable interface — and its initializer is
/// internal, so a value can only be made through the raw arena API. Shipping a
/// generator for it would put `@_spi(RawSyntax) import SwiftSyntax` in a
/// library's public surface and pin this package to an interface upstream
/// reserves the right to break. The `RawTokenSyntax` / `RawExprSyntax`
/// placeholder slots in the corpus come from swift-syntax's own parser
/// internals, which its own test suite covers with that SPI.
public extension Gen where Value: SyntaxProtocol {

    /// A node of type `Value` from a freshly parsed tree.
    ///
    /// Each draw picks a template, weaves a discriminator into it, parses, and
    /// returns one node **castable to `Value`**. If the chosen template yields
    /// none, the search rotates deterministically through the remaining
    /// templates.
    ///
    /// - Precondition: at least one template in
    ///   `Gen<Syntax>.syntaxSourceTemplates` must contain a node of type
    ///   `Value`. Every node type this package ships an entry point for is
    ///   covered by `SyntaxNodeGeneratorTests.everyBaseNodeTypeIsReachable`; an
    ///   exotic type that appears in no template fails loudly here rather than
    ///   looping or returning something of the wrong kind.
    static func syntaxNode() -> Generator<Value, some SendableSequenceType> {
        let pool = SyntaxNodePool.typedPool(Value.self)
        return Gen<Int>.int(in: 0 ..< pool.count).map { pool[$0] }
    }
}

extension SyntaxNodePool {

    /// Every node of type `T` in the retained pool.
    ///
    /// **Filtered from the pool rather than parsed per draw**, for the same
    /// reason `Gen<Syntax>.syntax()` draws from it: a freshly parsed tree is
    /// dropped as soon as the caller keeps only one node from it, and a dropped
    /// tree's arena is reused, so its nodes' identities collide. Filtering the
    /// pool inherits its one-identity-per-node property, and costs one pass at
    /// generator-construction time instead of a parse per draw.
    ///
    /// - Precondition: the pool must contain at least one `T`. Every node type
    ///   this package ships an entry point for is covered by
    ///   `SyntaxNodeGeneratorTests`; an exotic type present in no template fails
    ///   loudly here rather than returning a substitute of the wrong kind.
    static func typedPool<T: SyntaxProtocol>(_ type: T.Type) -> [T] {
        let candidates = allNodes.compactMap { $0.as(T.self) }
        guard !candidates.isEmpty else {
            preconditionFailure(
                "No tree in the pool contains a \(T.self) node. Add a template "
                + "to `Gen<Syntax>.syntaxSourceTemplates` that produces one, or "
                + "supply a generator for this type directly — a generator that "
                + "cannot produce its own type is a gap, not something to paper "
                + "over with a substitute node."
            )
        }
        return candidates
    }

    /// Every node of the tree parsed for one template + round.
    static func nodes(template: Int, discriminator: Int) -> [Syntax] {
        var nodes: [Syntax] = []
        appendDescendants(
            of: Syntax(Parser.parse(source: source(template: template, discriminator: discriminator))),
            to: &nodes
        )
        return nodes
    }

    /// Source text for one pool tree: a **run of statements** whose count and
    /// template mix both vary with `discriminator`.
    ///
    /// A run rather than a single statement because `SyntaxIdentifier` keys on
    /// structural position — same-shaped trees contribute far fewer distinct
    /// nodes than they contain, so varying the shape is what makes the pool
    /// wide. The requested template always leads, so a caller asking for
    /// template N gets a tree containing it and `typedNode`'s rotation stays
    /// meaningful.
    ///
    /// Deterministic in its inputs, so the pool is rebuilt identically in every
    /// process.
    static func source(template: Int, discriminator: Int) -> String {
        let templates = Gen<Syntax>.syntaxSourceTemplates
        let span = statementCountRange.upperBound - statementCountRange.lowerBound + 1
        let count = statementCountRange.lowerBound + (discriminator % span)
        return (0 ..< count).map { offset in
            let index = offset == 0
                ? template
                : (template &+ offset &* 7 &+ discriminator)
            return templates[abs(index) % templates.count]
                .replacingOccurrences(of: "$0", with: String(discriminator &* 31 &+ offset))
        }.joined(separator: "\n")
    }
}
