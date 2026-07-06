import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// v3.6.0 — `@ValueSemanticTests` peer macro implementation.
///
/// Attaches to a `ValueSemantic` conformer and emits a peer
/// `<TypeName>ValueSemanticTests` struct with a single `@Test func` that calls
/// `checkValueSemanticPropertyLaws(for: <TypeName>.self)` — so a type that
/// adopts value semantics gets the copy-mutate-compare law (single-step +
/// multi-step interleaving) checked on every CI run. The ValueSemantic analog
/// of `@InteractionInvariantTests`.
///
/// Detection is inheritance-clause-name-based (the macro sees only the
/// decoratee's syntax): the primary declaration must list `ValueSemantic`. The
/// conformer itself supplies `makeProbe` / `Mutation` / `apply` (+ `Equatable`),
/// so — unlike the interaction macro — the emit references no `initialState` /
/// `reducer`. A missing requirement surfaces as a clear compile error from the
/// emitted test (PRD §5.7's "compile error beats silent fallthrough").
public struct ValueSemanticTestsMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let target = TargetDecl(declaration: declaration) else {
            context.diagnose(Diagnostic(
                node: declaration,
                message: PropertyLawDiagnostic.nonTypeDecl
            ))
            return []
        }
        let inheritedNames = inheritedTypeNames(of: target.inheritanceClause)
        guard inheritedNames.contains("ValueSemantic") else {
            context.diagnose(Diagnostic(
                node: declaration,
                message: PropertyLawDiagnostic.noValueSemanticConformance
            ))
            return []
        }
        return [emitPeerSuite(typeName: target.name)]
    }

    /// The four valid attach points (struct / class / enum / actor) + the
    /// inheritance clause used to confirm the `ValueSemantic` conformance.
    /// Mirrors `InteractionInvariantTestsMacro.TargetDecl`.
    private struct TargetDecl {
        let name: String
        let inheritanceClause: InheritanceClauseSyntax?

        init?(declaration: some DeclSyntaxProtocol) {
            if let decl = declaration.as(StructDeclSyntax.self) {
                self.name = decl.name.text
                self.inheritanceClause = decl.inheritanceClause
                return
            }
            if let decl = declaration.as(ClassDeclSyntax.self) {
                self.name = decl.name.text
                self.inheritanceClause = decl.inheritanceClause
                return
            }
            if let decl = declaration.as(EnumDeclSyntax.self) {
                self.name = decl.name.text
                self.inheritanceClause = decl.inheritanceClause
                return
            }
            if let decl = declaration.as(ActorDeclSyntax.self) {
                self.name = decl.name.text
                self.inheritanceClause = decl.inheritanceClause
                return
            }
            return nil
        }
    }

    private static func inheritedTypeNames(of clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap { $0.type.trimmedDescription }
    }

    private static func emitPeerSuite(typeName: String) -> DeclSyntax {
        """
        struct \(raw: typeName)ValueSemanticTests {
            @Test func valueSemantic_\(raw: typeName)() async throws {
                    try await checkValueSemanticPropertyLaws(for: \(raw: typeName).self)
                }
        }
        """
    }
}
