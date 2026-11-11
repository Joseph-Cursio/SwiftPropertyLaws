import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@Discoverable(group:)` peer macro implementation (PRD §5.5 round-
/// trip discovery, M5 marker layer).
///
/// The attribute exists purely as syntax for the discovery plugin to
/// inspect — see `RoundTripFinder` and `RoundTripSuggester`. The macro
/// emits no peer declarations; its job is to make `@Discoverable(...)`
/// a valid attribute name that the Swift compiler accepts.
///
/// We do issue one diagnostic: when the `group:` argument is anything
/// other than a string literal (e.g. a variable reference, a function
/// call), the discovery plugin can't read the group at scan time so
/// the attribute would silently fail to do its job. Surfacing a warning
/// lets the user fix the call site before they wonder why no HIGH-
/// confidence suggestion ever appears.
public struct DiscoverableMacro: PeerMacro {

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf _: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        if let nonLiteralArg = nonLiteralGroupArgument(of: node) {
            context.diagnose(Diagnostic(
                node: nonLiteralArg,
                message: PropertyLawDiagnostic.discoverableGroupNotLiteral
            ))
        }
        return []
    }

    /// Inspect the attribute's argument list; if a `group:` argument is
    /// supplied as something other than a single-segment string literal,
    /// return its expression so the diagnostic points at it. A missing
    /// argument list (the bare `@Discoverable` form) is fine — `group`
    /// stays nil and the suggester treats the function as ungrouped.
    private static func nonLiteralGroupArgument(of node: AttributeSyntax) -> ExprSyntax? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }
        for arg in arguments where arg.label?.text == "group" {
            if let literal = arg.expression.as(StringLiteralExprSyntax.self),
               literal.segments.count == 1,
               literal.segments.first?.is(StringSegmentSyntax.self) == true {
                return nil
            }
            return arg.expression
        }
        return nil
    }
}
