import PropertyLawCore
import SwiftSyntax

/// Pure SwiftSyntax helpers that walk a `MemberBlockSyntax` to extract the
/// syntactic info `DerivationStrategist` and `KnownProtocol` consumers need.
///
/// Lives in its own leaf target (depending only on `PropertyLawCore` +
/// `SwiftSyntax`, not the macro/`SwiftCompilerPlugin` machinery) so both the
/// macro impl (`PropertyLawMacroImpl`) and the discovery plugin
/// (`PropertyLawDiscoveryTool`) can share one copy without the plugin taking
/// a compile-time dependency on the macro target. This preserves PRD §9
/// Decision 4's macro/plugin separation while removing the previously
/// duplicated `MemberBlockInspector` / `PluginMemberInspector` twins.
public enum MemberBlockInspector {

    /// Stored properties declared in `memberBlock`, in source order.
    /// Returns only `let`/`var` declarations with explicit type
    /// annotations and no accessor block (`{ get/set }` style computed
    /// properties are skipped). Multi-binding lines like `let x: Int, y: Int`
    /// produce one entry per binding.
    public static func storedMembers(in memberBlock: MemberBlockSyntax) -> [StoredMember] {
        var result: [StoredMember] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            guard !isStaticOrClass(varDecl) else { continue }
            for binding in varDecl.bindings {
                if binding.accessorBlock != nil { continue }
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }
                guard let typeAnnotation = binding.typeAnnotation else { continue }
                let typeName = typeAnnotation.type.trimmedDescription
                result.append(StoredMember(
                    name: identifier.identifier.text,
                    typeName: typeName
                ))
            }
        }
        return result
    }

    /// True when the type's primary declaration body contains any `init`.
    /// Swift suppresses the synthesized memberwise initializer in that
    /// case — memberwise-Arbitrary derivation must fall through.
    public static func hasUserInit(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members
        where member.decl.as(InitializerDeclSyntax.self) != nil {
            return true
        }
        return false
    }

    /// User-declared initializers in `memberBlock`, in source order, for the
    /// Tier 6 `initializerBased` strategy. Async initializers are skipped
    /// entirely (they can't be lifted through a synchronous generator `map`);
    /// failable (`init?`) and throwing inits are captured with flags so the
    /// strategist can decline them while still reporting an accurate `.todo`
    /// reason. Initializers with a variadic parameter are skipped (their call
    /// shape doesn't compose into a fixed-arity `zip`).
    public static func initializers(in memberBlock: MemberBlockSyntax) -> [InitializerSignature] {
        var result: [InitializerSignature] = []
        for member in memberBlock.members {
            guard let initDecl = member.decl.as(InitializerDeclSyntax.self) else { continue }
            let effects = initDecl.signature.effectSpecifiers
            if effects?.asyncSpecifier != nil { continue }

            var parameters: [InitializerParameter] = []
            var hasVariadic = false
            for param in initDecl.signature.parameterClause.parameters {
                if param.ellipsis != nil { hasVariadic = true; break }
                let firstName = param.firstName.text
                let label = firstName == "_" ? nil : firstName
                parameters.append(InitializerParameter(
                    label: label,
                    typeName: param.type.trimmedDescription
                ))
            }
            if hasVariadic { continue }

            result.append(InitializerSignature(
                parameters: parameters,
                isFailable: initDecl.optionalMark != nil,
                isThrowing: effects?.throwsClause != nil
            ))
        }
        return result
    }

    private static func isStaticOrClass(_ decl: VariableDeclSyntax) -> Bool {
        decl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static) || mod.name.tokenKind == .keyword(.class)
        }
    }
}
