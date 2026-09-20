import SwiftSyntax

/// Walks function declarations and extracts the `FunctionSignature`
/// records that `RoundTripSuggester` consumes (PRD §5.5 cross-function
/// round-trip discovery, M5 scope).
///
/// Like `WitnessFinder`, this is deliberately syntactic — signature
/// shape only, no type resolution. Generic functions are skipped at
/// the finder because their type-binding would need inference outside
/// M5's syntactic scope. The `@Discoverable(group:)` attribute is read
/// here so the suggester sees a uniform per-function record.
enum RoundTripFinder {

    /// Walk a type-decl member block; return one signature per
    /// `FunctionDeclSyntax` member that is eligible for round-trip
    /// pairing. Initializers, deinit, computed properties, and other
    /// non-`func` members are intentionally ignored.
    static func findMembers(in memberBlock: MemberBlockSyntax) -> [FunctionSignature] {
        memberBlock.members.compactMap { member in
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else {
                return nil
            }
            return signature(from: funcDecl)
        }
    }

    /// Walk top-level statements; return one signature per top-level
    /// `FunctionDeclSyntax`. Type declarations and other top-level
    /// items are ignored — they are handled by the conformance pass.
    static func findTopLevel(in source: SourceFileSyntax) -> [FunctionSignature] {
        source.statements.compactMap { statement in
            guard let funcDecl = statement.item.as(FunctionDeclSyntax.self) else {
                return nil
            }
            return signature(from: funcDecl)
        }
    }

    /// Build a `FunctionSignature` from a `FunctionDeclSyntax`. Returns
    /// nil for declarations M5 deliberately skips (currently: any
    /// generic function — type-binding inference is out of scope).
    static func signature(from funcDecl: FunctionDeclSyntax) -> FunctionSignature? {
        if funcDecl.genericParameterClause != nil { return nil }

        let isStatic = funcDecl.modifiers.contains { mod in
            mod.name.tokenKind == .keyword(.static)
        }
        let parameters = funcDecl.signature.parameterClause.parameters
        let parameterTypes = parameters.map { $0.type.trimmedDescription }
        let returnType = funcDecl.signature.returnClause?.type.trimmedDescription ?? "Void"

        return FunctionSignature(
            name: funcDecl.name.text,
            parameterTypes: parameterTypes,
            returnType: returnType,
            isStatic: isStatic,
            group: discoverableGroup(in: funcDecl.attributes)
        )
    }

    /// Extract the `group:` argument from a `@Discoverable(group: "…")`
    /// attribute. Only string-literal arguments are honored — other
    /// shapes (variable references, interpolated strings) leave `group`
    /// nil rather than misrecord. This matches `WitnessFinder`'s stance
    /// of preferring "no signal" over "wrong signal" for ambiguous
    /// syntactic forms.
    private static func discoverableGroup(in attributes: AttributeListSyntax) -> String? {
        for attribute in attributes {
            guard let attributeSyntax = attribute.as(AttributeSyntax.self) else { continue }
            guard attributeSyntax.attributeName.trimmedDescription == "Discoverable" else {
                continue
            }
            guard let arguments = attributeSyntax.arguments?.as(LabeledExprListSyntax.self) else {
                continue
            }
            for arg in arguments where arg.label?.text == "group" {
                if let literal = arg.expression.as(StringLiteralExprSyntax.self),
                   literal.segments.count == 1,
                   let segment = literal.segments.first?.as(StringSegmentSyntax.self) {
                    return segment.content.text
                }
            }
        }
        return nil
    }
}
