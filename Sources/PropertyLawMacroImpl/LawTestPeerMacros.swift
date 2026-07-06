import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// Shared implementation for the retroactive-law test macros —
/// `@ValueSemanticTests` (v3.6.0), `@DefensiveCopyTests` + `@StableIdentityTests`
/// (v3.9.0). Each attaches to a conformer of a kit law protocol and emits a peer
/// `@Suite` struct whose single `@Test func` calls the matching runtime harness,
/// so a type adopting the law gets it checked on every CI run. The three differ
/// only by protocol name + harness function, so the expansion lives here once.
///
/// Detection is inheritance-clause-name-based (the macro sees only the
/// decoratee's syntax): the primary declaration must list the protocol. The
/// conformer supplies the protocol's requirements, so a missing one surfaces as
/// a compile error from the emitted test (PRD §5.7's "compile error beats silent
/// fallthrough").
enum LawTestPeerMacro {

    struct Config {
        let protocolName: String        // "ValueSemantic"
        let suffix: String              // "ValueSemanticTests"
        let testFragment: String        // "valueSemantic"
        let checkFunction: String       // "checkValueSemanticPropertyLaws"
        let missingConformance: PropertyLawDiagnostic
    }

    static func expansion(
        _ config: Config,
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) -> [DeclSyntax] {
        guard let target = TargetDecl(declaration: declaration) else {
            context.diagnose(Diagnostic(node: declaration, message: PropertyLawDiagnostic.nonTypeDecl))
            return []
        }
        guard inheritedTypeNames(of: target.inheritanceClause).contains(config.protocolName) else {
            context.diagnose(Diagnostic(node: declaration, message: config.missingConformance))
            return []
        }
        return [emitPeerSuite(typeName: target.name, config: config)]
    }

    /// The four valid attach points (struct / class / enum / actor) + the
    /// inheritance clause used to confirm the conformance.
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

    private static func emitPeerSuite(typeName: String, config: Config) -> DeclSyntax {
        """
        struct \(raw: typeName)\(raw: config.suffix) {
            @Test func \(raw: config.testFragment)_\(raw: typeName)() async throws {
                    try await \(raw: config.checkFunction)(for: \(raw: typeName).self)
                }
        }
        """
    }
}

/// v3.6.0 — `@ValueSemanticTests` (copy-mutate-compare, Ch. 9 §9.1–§9.2).
public struct ValueSemanticTestsMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        LawTestPeerMacro.expansion(
            .init(
                protocolName: "ValueSemantic",
                suffix: "ValueSemanticTests",
                testFragment: "valueSemantic",
                checkFunction: "checkValueSemanticPropertyLaws",
                missingConformance: .noValueSemanticConformance
            ),
            of: node, providingPeersOf: declaration, in: context
        )
    }
}

/// v3.9.0 — `@DefensiveCopyTests` (distinct + independent copy, Ch. 9 §9.3.2).
public struct DefensiveCopyTestsMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        LawTestPeerMacro.expansion(
            .init(
                protocolName: "DefensiveCopy",
                suffix: "DefensiveCopyTests",
                testFragment: "defensiveCopy",
                checkFunction: "checkDefensiveCopyPropertyLaws",
                missingConformance: .noDefensiveCopyConformance
            ),
            of: node, providingPeersOf: declaration, in: context
        )
    }
}

/// v3.9.0 — `@StableIdentityTests` (identity invariant under mutation, Ch. 9 §9.3.3).
public struct StableIdentityTestsMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        LawTestPeerMacro.expansion(
            .init(
                protocolName: "StableIdentity",
                suffix: "StableIdentityTests",
                testFragment: "stableIdentity",
                checkFunction: "checkStableIdentityPropertyLaws",
                missingConformance: .noStableIdentityConformance
            ),
            of: node, providingPeersOf: declaration, in: context
        )
    }
}
