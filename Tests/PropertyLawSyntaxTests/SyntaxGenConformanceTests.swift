import PropertyBased
import PropertyLawKit
import SwiftSyntax
import Testing
import PropertyLawSyntax

/// The discovery plugin renders a `.todo` strategy as `"\(typeName).gen()"`, so
/// a generated suite for `Syntax` already reads
/// `using: Syntax.gen()` — it just had no such method. These extensions supply
/// it, which is why **no emitter change was needed** to close 303 `Syntax` slots
/// and 34 `ExprSyntax` ones.
///
/// This file deliberately uses a plain `import PropertyLawSyntax` rather than
/// `@testable`: it is standing in for a consumer's generated file, and anything
/// not public here would surface as a compile error at exactly the point a real
/// consumer would hit it.
struct SyntaxGenConformanceTests {

    /// The literal shape the plugin emits, compiled and run. If `gen()` were
    /// missing or non-public this file would not build — which is the assertion.
    @Test("the emitted `Type.gen()` spelling compiles and runs for Syntax")
    func syntaxGenMatchesEmittedSpelling() async throws {
        try await checkHashablePropertyLaws(
            for: Syntax.self,
            using: Syntax.gen(),
            options: LawCheckOptions(budget: .sanity)
        )
    }

    @Test("every shipped node type answers gen()")
    func everyNodeTypeAnswersGen() {
        var rng = Xoshiro(seed: (1, 2, 3, 4))
        #expect(Syntax.gen().run(using: &rng).description.isEmpty == false)
        _ = ExprSyntax.gen().run(using: &rng)
        _ = DeclSyntax.gen().run(using: &rng)
        _ = StmtSyntax.gen().run(using: &rng)
        _ = PatternSyntax.gen().run(using: &rng)
        _ = TypeSyntax.gen().run(using: &rng)
        _ = TokenSyntax.gen().run(using: &rng)
    }

    /// `gen()` must be the same generator, not a second implementation that
    /// could drift from the measured distribution behaviour.
    @Test("gen() delegates to the documented generator")
    func genDelegates() {
        var lhs = Xoshiro(seed: (7, 8, 9, 10))
        var rhs = Xoshiro(seed: (7, 8, 9, 10))
        let viaGen = (0 ..< 20).map { _ in Syntax.gen().run(using: &lhs).description }
        let viaFactory = (0 ..< 20).map { _ in Gen<Syntax>.syntax().run(using: &rhs).description }
        #expect(viaGen == viaFactory)
    }
}
