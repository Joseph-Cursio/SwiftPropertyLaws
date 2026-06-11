import PropertyLawCore
import PropertyLawSyntaxSupport
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@PropertyLawSuite` peer macro implementation.
///
/// Given a type declaration, reads its inheritance clause, filters down to
/// the most-specific recognized stdlib conformances (PRD §4.3 inheritance
/// rule), derives a generator via `DerivationStrategist` (PRD §5.7), and
/// emits a peer struct of `@Test func` methods — one per surviving
/// conformance, calling the corresponding `checkXxxPropertyLaws(...)`
/// against the derived (or user-provided) generator.
///
/// `IteratorProtocol`-only conformers receive no emit because the kit's
/// `checkIteratorProtocolPropertyLaws` is parameterized over a host `Sequence`.
public struct PropertyLawSuiteMacro: PeerMacro {

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
        let conformances = KnownProtocol.set(from: inheritedNames)
        let macroEmittable = conformances.subtracting(KnownProtocol.unemittable)
        let emitSet = KnownProtocol.mostSpecific(in: macroEmittable)
        if emitSet.isEmpty {
            context.diagnose(Diagnostic(
                node: declaration,
                message: PropertyLawDiagnostic.noKnownConformance
            ))
            return []
        }
        let shape = TypeShape(
            name: target.name,
            kind: target.kind,
            inheritedTypes: inheritedNames,
            hasUserGen: target.hasUserGen,
            storedMembers: target.storedMembers,
            hasUserInit: target.hasUserInit
        )
        let strategy = DerivationStrategist.strategy(for: shape)
        if case .todo(let reason) = strategy {
            context.diagnose(Diagnostic(
                node: declaration,
                message: PropertyLawDiagnostic.cannotDeriveGenerator(reason: reason)
            ))
        }
        return [emitPeerSuite(typeName: target.name, conformances: emitSet, strategy: strategy)]
    }

    /// One of the four type-decl shapes a peer macro can attach to. Bundles
    /// the type name + inheritance clause + member-block info so the rest
    /// of the expansion is kind-agnostic.
    private struct TargetDecl {
        let name: String
        let kind: TypeShape.Kind
        let inheritanceClause: InheritanceClauseSyntax?
        let hasUserGen: Bool
        let storedMembers: [StoredMember]
        let hasUserInit: Bool

        init?(declaration: some DeclSyntaxProtocol) {
            if let decl = declaration.as(StructDeclSyntax.self) {
                self = TargetDecl(
                    name: decl.name.text,
                    kind: .struct,
                    inheritanceClause: decl.inheritanceClause,
                    memberBlock: decl.memberBlock
                )
                return
            }
            if let decl = declaration.as(ClassDeclSyntax.self) {
                self = TargetDecl(
                    name: decl.name.text,
                    kind: .class,
                    inheritanceClause: decl.inheritanceClause,
                    memberBlock: decl.memberBlock
                )
                return
            }
            if let decl = declaration.as(EnumDeclSyntax.self) {
                self = TargetDecl(
                    name: decl.name.text,
                    kind: .enum,
                    inheritanceClause: decl.inheritanceClause,
                    memberBlock: decl.memberBlock
                )
                return
            }
            if let decl = declaration.as(ActorDeclSyntax.self) {
                self = TargetDecl(
                    name: decl.name.text,
                    kind: .actor,
                    inheritanceClause: decl.inheritanceClause,
                    memberBlock: decl.memberBlock
                )
                return
            }
            return nil
        }

        init(
            name: String,
            kind: TypeShape.Kind,
            inheritanceClause: InheritanceClauseSyntax?,
            memberBlock: MemberBlockSyntax
        ) {
            self.name = name
            self.kind = kind
            self.inheritanceClause = inheritanceClause
            self.hasUserGen = Self.hasGenMethod(in: memberBlock)
            self.storedMembers = MemberBlockInspector.storedMembers(in: memberBlock)
            self.hasUserInit = MemberBlockInspector.hasUserInit(in: memberBlock)
        }

        /// Scans the type's primary declaration body for a static `gen()`
        /// method. Misses extension-defined `gen()` (the macro can't see
        /// siblings) — users who want to override a derivable type's
        /// auto-generator must put `gen()` in the type's primary body.
        private static func hasGenMethod(in memberBlock: MemberBlockSyntax) -> Bool {
            for member in memberBlock.members {
                guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
                guard funcDecl.name.text == "gen" else { continue }
                let isStatic = funcDecl.modifiers.contains { mod in
                    mod.name.tokenKind == .keyword(.static)
                }
                if isStatic { return true }
            }
            return false
        }
    }

    private static func inheritedTypeNames(of clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap { $0.type.trimmedDescription }
    }

    private static func emitPeerSuite(
        typeName: String,
        conformances: Set<KnownProtocol>,
        strategy: DerivationStrategy
    ) -> DeclSyntax {
        let generatorExpr = GeneratorExpressionEmitter.expression(
            typeName: typeName,
            strategy: strategy
        )
        let testMethods = stableOrder(conformances).map { conformance in
            emitTest(conformance: conformance, typeName: typeName, generatorExpr: generatorExpr)
        }.joined(separator: "\n\n    ")
        return """
            struct \(raw: typeName)PropertyLawTests {
                \(raw: testMethods)
            }
            """
    }

    /// Stable iteration order so the emit is deterministic across runs —
    /// the user reads a diff of generated tests, not a re-shuffle.
    private static func stableOrder(_ protocols: Set<KnownProtocol>) -> [KnownProtocol] {
        KnownProtocol.allCases.filter { protocols.contains($0) }
    }

    private static func emitTest(
        conformance: KnownProtocol,
        typeName: String,
        generatorExpr: String
    ) -> String {
        let testFuncName = "\(conformance.testNameFragment)_\(typeName)"
        let checkFn = conformance.checkFunctionName
        return """
            @Test func \(testFuncName)() async throws {
                    try await \(checkFn)(
                        for: \(typeName).self,
                        using: \(generatorExpr)
                    )
                }
            """
    }
}
