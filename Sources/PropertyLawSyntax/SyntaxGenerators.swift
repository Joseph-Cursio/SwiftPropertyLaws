import Foundation
import PropertyBased
import SwiftParser
import SwiftSyntax

/// Generators for `SwiftSyntax.Syntax`.
///
/// **Why this exists.** Pointing the discovery plugin at swift-syntax leaves
/// `Syntax` as the single largest derivation gap in the corpus: 303 of the
/// scaffolded placeholder slots ask for a `Generator<Syntax, _>`, because
/// `Syntax`'s stored properties are an opaque arena (`SyntaxDataArena`,
/// `SyntaxDataReference`) that no derivation tier can construct. One
/// hand-written generator unblocks all of them.
///
/// **`Syntax` identity is allocation-scoped, and that decides the design.**
/// This file got it wrong twice before measuring properly, so the record is
/// here rather than the conclusion alone.
///
/// `Syntax.==` and `hashValue` are both `SyntaxIdentifier`:
///
/// ```swift
/// public static func == (lhs: Syntax, rhs: Syntax) -> Bool { lhs.id == rhs.id }
/// ```
///
/// 1. **First attempt — a fixed 32-node pool**, so repeats made the Equatable
///    antecedent fire. It failed `Hashable.distribution` against correct code:
///    *"1000 samples produced only 32 unique hashValues (ratio 0.032)"* under a
///    0.10 threshold. Rejected — a generator that makes a correct library look
///    broken is the `BitSet.Counted` failure mode.
/// 2. **Second attempt — parse a fresh tree per draw**, on the reasoning that a
///    new tree means a new identity at any budget. **It does not.** Identity
///    keys on structural position, so 100 sources of identical shape and wholly
///    different tokens produced *one* distinct id; and varying the shape did not
///    rescue it either, because the id is tied to the tree's **arena**, which is
///    freed the moment the tree is dropped and whose address is then reused.
///    Measured: 300 parsed-and-dropped trees yielded **78** unique ids, and the
///    generator gave 751 unique in 10 000 draws — ratio 0.075, *failing* the
///    same law at `.exhaustive` that attempt 1 was rejected for.
/// 3. **What actually works — a large pool whose trees stay alive.** The same
///    300 trees, retained, yield **11 700 unique ids from 11 700 nodes**: every
///    node distinct. Identity is available exactly as long as the arena is.
///
/// So the pool was right and the reason for rejecting it was wrong: a pool does
/// cap unique hashes at its size, but the alternative caps them *lower*. Sizing
/// is the whole game — `distribution` needs `poolSize > budget / 10`, so
/// `defaultPoolSize` is set for `.exhaustive` with room to spare.
///
/// The cost of that, stated plainly: `a == b` between two draws happens at
/// `1 / poolSize`, so the Equatable laws needing an equal pair are close to
/// vacuous. For identity equality those are theorems about `SyntaxIdentifier`
/// rather than risks, and reflexivity still covers "the same node compares equal
/// and hashes the same". `pooled(size:)` is there when you want the antecedent
/// to fire and will accept the distribution violation that comes with it.
public extension Gen where Value == Syntax {

    /// Source templates the generator parses.
    ///
    /// Each contains `$0`, replaced by a per-draw discriminator so no two draws
    /// parse the same text — that is what keeps hash distribution independent of
    /// the trial budget.
    ///
    /// Order is part of the API: a counterexample report can name
    /// `syntaxSourceTemplates[i]` to say which shape a failure came from. New
    /// entries append; existing indices never shift.
    ///
    /// Chosen for **node-kind breadth** rather than realism — each template is
    /// here because it contributes kinds the others do not (declarations,
    /// statements, patterns, generics, closures, attributes, operators,
    /// interpolation, trivia).
    static var syntaxSourceTemplates: [String] {
        [
            "let x$0 = $0",                                                     // 0
            "var greeting$0: String = \"hello $0\"",                            // 1
            "struct Point$0 { let x: Int; let y: Int }",                        // 2
            "enum Direction$0 { case north, south(distance: Int) }",            // 3
            "func add$0(_ a: Int, to b: Int) -> Int { a + b }",                 // 4
            "if a$0 > b { print(a$0) } else { print(b) }",                      // 5
            "for item in items$0 where item.isValid { total += item.count }",   // 6
            "let doubled$0 = values.map { $$0 * $0 }.filter { $$0 > 10 }",      // 7
            "protocol Shape$0: Sendable { associatedtype Unit: Numeric }",      // 8
            "extension Array where Element: Equatable { func f$0() {} }",       // 9
            "@MainActor final class Store$0<T>: ObservableObject { }",          // 10
            "let message$0 = \"total: \\(count) items\" // comment $0",          // 11
            "guard let value$0 = optional else { return nil }",                 // 12
            "do { try risky$0() } catch let error as MyError { log(error) }",   // 13
            // 14 — dictionary and array literals. Added on a downstream
            // consumer's measured request: `DictionaryExprSyntax` was the one
            // of six requested node types no template contained.
            "let table$0 = [\"a\": 1, \"b\": $0]; let list$0 = [1, 2, $0]"     // 14
        ]
    }

    /// Pool size for `syntax()`.
    ///
    /// `Hashable.distribution` fails under a 0.10 unique-hash ratio, and a pool
    /// of `N` yields exactly `N` unique hashes, so the pool must exceed
    /// `budget / 10`. 4 096 clears the kit's largest budget (`.exhaustive`,
    /// 10 000 trials → 0.41) with room for a caller who raises it further.
    static var defaultPoolSize: Int { 4096 }

    /// A `Syntax` node from the retained pool — **the default**.
    ///
    /// The pool is built once and **held for the process**, which is what makes
    /// its nodes' identities distinct and stable — see the type documentation.
    /// Building it parses a few hundred small sources; that happens lazily on
    /// first use and never again.
    static func syntax() -> Generator<Syntax, some SendableSequenceType> {
        pooled(size: Gen<Syntax>.defaultPoolSize)
    }

    /// A `Syntax` node drawn from a **fixed pool**, so that two draws can be the
    /// same node and therefore compare equal.
    ///
    /// For a binary law over `(a, b)` the equality antecedent fires at
    /// `1 / size`. Use this when you specifically want symmetry or
    /// `equalityConsistency` to have something to chew on.
    ///
    /// **It will trip `Hashable.distribution`** once the trial budget exceeds
    /// roughly `10 × size`, because unique hashes cap at the pool size against a
    /// budget-sized denominator — measured at size 32 / 1 000 trials as *"only
    /// 32 unique hashValues (ratio 0.032)"* under a 0.10 threshold. Pair it with
    /// `laws: .ownOnly` and a budget you have checked, or expect a Heuristic
    /// violation that is an artefact of the pool rather than a fact about
    /// `Syntax`.
    ///
    /// Ternary laws stay out of reach either way: transitivity needs
    /// `a == b && b == c`, which fires at `1 / size²`, and no size fixes that —
    /// independent sampling cannot correlate three draws.
    static func pooled(size: Int) -> Generator<Syntax, some SendableSequenceType> {
        let pool = SyntaxNodePool.pool(size: size)
        return Gen<Int>.int(in: 0 ..< pool.count).map { pool[$0] }
    }
}

/// Tree construction behind the `Syntax` generators.
enum SyntaxNodePool {

    /// One node of the tree parsed for `template`/`discriminator`, chosen by
    /// `nodeIndex` modulo the tree's node count.
    ///
    /// `nodeIndex` is taken modulo rather than rejected so the generator is
    /// total: templates parse to different node counts, and a rejection loop
    /// would make draw cost depend on which template came up.
    static func node(template: Int, discriminator: Int, nodeIndex: Int) -> Syntax {
        let all = nodes(template: template, discriminator: discriminator)
        return all[nodeIndex % all.count]
    }

    /// How many statements a generated source may contain.
    ///
    /// **This is the knob that makes hash distribution work, and the first
    /// version of this file got it wrong.** `SyntaxIdentifier` — which is what
    /// `Syntax.==` and `hashValue` are — keys on a node's *structural position*,
    /// not on its text. Measured: 100 sources of identical shape and completely
    /// different tokens produced **one** distinct id. So weaving a
    /// discriminator into the tokens, which is what the original design did,
    /// created no identities whatsoever, and the generator's whole identity
    /// space was `templates × nodes-per-template`: **10 000 draws gave 751
    /// unique ids, ratio 0.075, under the 0.10 threshold.** The fixed pool this
    /// design was chosen over would have failed at `.exhaustive`, and so did
    /// this — the claim that fresh parsing kept distribution healthy "at any
    /// budget" was simply false.
    ///
    /// Varying the statement *count* varies the structure, and structure is
    /// what identity is made of: trees of 1...40 statements yield 10 686
    /// distinct ids where 40 fixed-shape trees yield ~40.
    static let statementCountRange = 1 ... 12

    /// Every node of every tree in the pool, in a deterministic order.
    ///
    /// **Held for the process, and that retention is the point.** A node's
    /// `SyntaxIdentifier` lives as long as its tree's arena; drop the tree and
    /// the address is recycled, so ids collide. Measured: 300 parsed-and-dropped
    /// trees gave 78 unique ids, the same 300 retained gave 11 700. Keeping the
    /// array alive is what makes every node a distinct value.
    ///
    /// One tree per (template, round): rounds vary the statement count and the
    /// template mix, so trees differ in **shape** and not merely in tokens —
    /// identity keys on structure, so same-shaped trees would contribute
    /// far fewer distinct nodes than they do nodes.
    ///
    /// Built once, lazily. Parsing is pure, so this is stable within a process
    /// and rebuilt identically in the next. `Syntax` is `Sendable`, so the
    /// flattened array is too.
    static let allNodes: [Syntax] = {
        var nodes: [Syntax] = []
        var round = 0
        // Grow until the pool clears the largest budget the kit ships
        // (`.exhaustive`, 10 000 trials, needing > 1 000 nodes), with the round
        // cap as a backstop so a template-list edit cannot spin here.
        while nodes.count < Gen<Syntax>.defaultPoolSize && round < 64 {
            for template in Gen<Syntax>.syntaxSourceTemplates.indices {
                let text = SyntaxNodePool.source(template: template, discriminator: round)
                appendDescendants(of: Syntax(Parser.parse(source: text)), to: &nodes)
            }
            round += 1
        }
        return nodes
    }()

    /// `size` nodes spread evenly across `allNodes`.
    ///
    /// **Strided rather than prefixed.** Taking the first `size` nodes would
    /// draw them all from the first template or two — the flattened order is
    /// depth-first per template — so the pool would be a handful of node kinds
    /// from one shape. A stride samples across every template, which is the
    /// variety the template list was chosen for.
    static func pool(size: Int) -> [Syntax] {
        let nodes = allNodes
        guard size > 0 else { return [nodes[0]] }
        guard size < nodes.count else { return nodes }
        let step = Double(nodes.count) / Double(size)
        return (0 ..< size).map { nodes[Int(Double($0) * step)] }
    }

    static func appendDescendants(of node: Syntax, to nodes: inout [Syntax]) {
        nodes.append(node)
        for child in node.children(viewMode: .sourceAccurate) {
            appendDescendants(of: child, to: &nodes)
        }
    }
}
