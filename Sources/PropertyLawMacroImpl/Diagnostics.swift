import PropertyLawCore
import SwiftDiagnostics

/// Diagnostic messages emitted by `@PropertyLawSuite` expansion. Each case
/// has a stable `MessageID.id` so users can suppress per-rule via
/// upstream tooling.
/// Diagnostic identity. The dynamic-message variant
/// `cannotDeriveGenerator(_:)` carries the strategist's reason verbatim
/// so the user sees the same text the discovery plugin would print.
internal enum PropertyLawDiagnostic: DiagnosticMessage {
    /// Macro applied to a non-type declaration (function, property,
    /// extension, etc.). Compilers usually reject the attachment before
    /// the macro runs, but we surface a clear message for the cases
    /// where the attribute slips through.
    case nonTypeDecl

    /// The decoratee conforms to no recognized stdlib protocol — nothing
    /// to emit.
    case noKnownConformance

    /// Generator derivation fell through to `.todo` — the macro will emit
    /// `<TypeName>.gen()` as a placeholder reference, which produces a
    /// compile error pointing at the missing symbol. PRD §5.7 telemetry
    /// requirement: surface which strategy was attempted and why.
    case cannotDeriveGenerator(reason: String)

    /// `@Discoverable(group:)` was supplied a non-literal argument
    /// (variable ref, interpolated string, etc.). The discovery plugin
    /// only reads string literals at scan time — see `RoundTripFinder`
    /// — so the group would silently fail to bind. Surface a warning
    /// so the user knows to inline the literal.
    case discoverableGroupNotLiteral

    /// v2.5.0 — `@InteractionInvariantTests` decoratee has no
    /// recognized family-protocol conformance in its inheritance
    /// clause. Either the type doesn't conform to any of the five
    /// v2.3.0 family sub-protocols, or the conformance is declared
    /// in an extension outside the type's primary declaration (the
    /// macro can't see siblings). No peer is emitted.
    case noInteractionInvariantConformance

    /// v3.6.0 — `@ValueSemanticTests` on a type whose primary declaration's
    /// inheritance clause doesn't list `ValueSemantic` (or the conformance is
    /// declared in an extension the macro can't see). No peer is emitted.
    case noValueSemanticConformance

    var message: String {
        switch self {
        case .nonTypeDecl:
            return "@PropertyLawSuite must decorate a struct, class, enum, or actor."
        case .noKnownConformance:
            // Built from `KnownProtocol.allCases.declarationName` so the
            // list stays in sync as the kit adds protocols — past stale
            // versions of this string lagged v1.1 and v1.2 by months.
            let recognized = KnownProtocol.allCases
                .map(\.declarationName)
                .joined(separator: ", ")
            return "Type has no recognized stdlib protocol conformance — no "
                + "law checks emitted. Recognized protocols: \(recognized). "
                + "Conformances declared via extensions outside the type's "
                + "primary declaration aren't visible to the macro (it sees "
                + "only the decoratee's syntax); whole-module discovery "
                + "(PRD §5.3) handles those cases."
        case .cannotDeriveGenerator(let reason):
            return reason
        case .discoverableGroupNotLiteral:
            return "@Discoverable(group:) requires a string literal — the "
                + "discovery plugin reads the value at scan time and can't "
                + "evaluate variable references or computed strings. "
                + "Replace with an inline string literal so the function is "
                + "matched by group-based round-trip discovery."
        case .noInteractionInvariantConformance:
            return "@InteractionInvariantTests requires the decoratee to "
                + "conform to one of the five v2.3.0 family protocols in its "
                + "primary declaration's inheritance clause: "
                + "CardinalityInvariant, ReferentialIntegrityInvariant, "
                + "BiconditionalInvariant, ConservationInvariant, "
                + "ActionIdempotenceInvariant (or the root InteractionInvariant). "
                + "Conformances declared via extensions outside the type's "
                + "primary declaration aren't visible to the macro."
        case .noValueSemanticConformance:
            return "@ValueSemanticTests requires the decoratee to conform to "
                + "ValueSemantic in its primary declaration's inheritance clause. "
                + "Conformances declared via extensions outside the type's "
                + "primary declaration aren't visible to the macro."
        }
    }

    var diagnosticID: MessageID {
        let id: String
        switch self {
        case .nonTypeDecl: id = "nonTypeDecl"
        case .noKnownConformance: id = "noKnownConformance"
        case .cannotDeriveGenerator: id = "cannotDeriveGenerator"
        case .discoverableGroupNotLiteral: id = "discoverableGroupNotLiteral"
        case .noInteractionInvariantConformance: id = "noInteractionInvariantConformance"
        case .noValueSemanticConformance: id = "noValueSemanticConformance"
        }
        return MessageID(domain: "PropertyLawMacro", id: id)
    }

    var severity: DiagnosticSeverity {
        switch self {
        case .nonTypeDecl: return .error
        case .noKnownConformance, .cannotDeriveGenerator,
             .discoverableGroupNotLiteral,
             .noInteractionInvariantConformance,
             .noValueSemanticConformance:
            return .warning
        }
    }
}
