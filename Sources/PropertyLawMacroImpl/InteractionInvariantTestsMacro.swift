import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// v2.5.0 — the five interaction-invariant families recognized by
/// `@InteractionInvariantTests`. Carries the per-family emit
/// metadata (which harness to call + which test-name fragment to
/// use). Detection is inheritance-clause-name-based; the macro
/// can't see across files.
internal enum InteractionInvariantFamily {
    case cardinality
    case referentialIntegrity
    case biconditional
    case conservation
    case interactionRoot
    case actionIdempotence

    /// Detect which family's protocol the conformer extends. Order
    /// matters: `ActionIdempotenceInvariant` is checked first
    /// because it refines the root and would also satisfy the
    /// "extends InteractionInvariant" check; matching it first
    /// routes to the correct harness.
    static func detect(in inheritedNames: [String]) -> Self? {
        if inheritedNames.contains("ActionIdempotenceInvariant") {
            return .actionIdempotence
        }
        if inheritedNames.contains("CardinalityInvariant") {
            return .cardinality
        }
        if inheritedNames.contains("ReferentialIntegrityInvariant") {
            return .referentialIntegrity
        }
        if inheritedNames.contains("BiconditionalInvariant") {
            return .biconditional
        }
        if inheritedNames.contains("ConservationInvariant") {
            return .conservation
        }
        if inheritedNames.contains("InteractionInvariant") {
            return .interactionRoot
        }
        return nil
    }

    /// Which harness to call. Action-idempotence routes to the
    /// double-application harness; the other four route to the
    /// state-predicate harness (the root + all 4 refinements share
    /// the `invariantHolds(in:)` semantics).
    var checkFunctionName: String {
        switch self {
        case .actionIdempotence:
            return "checkActionIdempotenceInvariantPropertyLaws"

        case .cardinality, .referentialIntegrity, .biconditional,
             .conservation, .interactionRoot:
            return "checkInteractionInvariantPropertyLaws"
        }
    }

    /// Test-method-name fragment. Same posture as
    /// `KnownProtocol.testNameFragment` — produces a stable,
    /// human-readable function name that includes the family
    /// without colliding across emits.
    var testNameFragment: String {
        switch self {
        case .cardinality: return "cardinalityInvariant"
        case .referentialIntegrity: return "referentialIntegrityInvariant"
        case .biconditional: return "biconditionalInvariant"
        case .conservation: return "conservationInvariant"
        case .interactionRoot: return "interactionInvariant"
        case .actionIdempotence: return "actionIdempotenceInvariant"
        }
    }
}

/// v2.5.0 — `@InteractionInvariantTests` peer macro implementation.
///
/// Reads the decoratee's inheritance clause for one of the five
/// interaction-invariant family sub-protocols (PRD §9 / v2.3.0
/// protocol family); emits a peer
/// `<TypeName>InteractionInvariantTests` struct with a single
/// `@Test func` calling the appropriate v2.4.0 harness:
///
/// - `CardinalityInvariant` / `ReferentialIntegrityInvariant` /
///   `BiconditionalInvariant` / `ConservationInvariant` /
///   `InteractionInvariant` → `checkInteractionInvariantPropertyLaws`.
/// - `ActionIdempotenceInvariant` → `checkActionIdempotenceInvariantPropertyLaws`.
///
/// The emit references `Self.initialState` and `Self.reducer` — the
/// user must define both on the conformer. A missing member surfaces
/// as a clear compile error from the emitted test code, matching
/// `@PropertyLawSuite`'s "missing `gen()`" posture (PRD §5.7's
/// "compile error beats silent fallthrough").
public struct InteractionInvariantTestsMacro: PeerMacro {

    public static func expansion(
        of _: AttributeSyntax,
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
        guard let family = InteractionInvariantFamily.detect(in: inheritedNames) else {
            context.diagnose(Diagnostic(
                node: declaration,
                message: PropertyLawDiagnostic.noInteractionInvariantConformance
            ))
            return []
        }
        return [emitPeerSuite(typeName: target.name, family: family)]
    }

    /// Type-decl shape bundle. Same posture as `PropertyLawSuiteMacro`'s
    /// `TargetDecl` — the four valid attach points (struct / class /
    /// enum / actor) and the inheritance clause needed to detect
    /// which family protocol is in use.
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
        return clause.inheritedTypes.compactMap(\.type.trimmedDescription)
    }

    private static func emitPeerSuite(
        typeName: String,
        family: InteractionInvariantFamily
    ) -> DeclSyntax {
        let testFuncName = "\(family.testNameFragment)_\(typeName)"
        let checkFn = family.checkFunctionName
        return """
            struct \(raw: typeName)InteractionInvariantTests {
                @Test func \(raw: testFuncName)() async throws {
                        try await \(raw: checkFn)(
                            for: \(raw: typeName).self,
                            initialState: \(raw: typeName).initialState,
                            reducer: \(raw: typeName).reducer
                        )
                    }
            }
            """
    }
}
