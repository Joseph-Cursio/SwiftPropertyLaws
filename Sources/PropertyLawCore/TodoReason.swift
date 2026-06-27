/// Human-readable `.todo` diagnostics — split out of `DerivationStrategy`
/// so that file stays focused on the strategy machinery. Surfaced as the
/// macro's warning alongside the deliberate compile error (PRD §5.7).
extension DerivationStrategist {

    /// Explanation for why no strategy applied, by type kind.
    static func todoReason(for shape: TypeShape) -> String {
        switch shape.kind {
        case .enum:
            return "Cannot derive a generator for `\(shape.name)`: not "
                + "`CaseIterable` and no recognized stdlib raw type. Provide "
                + "`static func gen() -> Generator<\(shape.name), some "
                + "SendableSequenceType>` or add `: CaseIterable`."
        case .struct:
            return structTodoReason(for: shape)
        case .class, .actor:
            return "Cannot derive a generator for `\(shape.name)`: memberwise "
                + "derivation supports structs only (class/actor reference "
                + "semantics complicate the synthesized-init contract). "
                + "Provide `static func gen() -> Generator<\(shape.name), "
                + "some SendableSequenceType>`."
        }
    }

    /// Diagnostic for struct cases that fell through memberwise derivation
    /// — names the specific reason so the user knows whether to add a
    /// `gen()` or restructure the type.
    private static func structTodoReason(for shape: TypeShape) -> String {
        let prefix = "Cannot derive a generator for `\(shape.name)`: "
        let suffix = " Provide `static func gen() -> Generator<\(shape.name), "
            + "some SendableSequenceType>`."
        if shape.storedMembers.isEmpty {
            return prefix + "the type's primary declaration has no stored "
                + "properties visible to the macro." + suffix
        }
        if shape.hasUserInit {
            if shape.initializers.isEmpty {
                return prefix + "the type declares a user `init(...)` in its "
                    + "primary body, which suppresses Swift's synthesized "
                    + "memberwise initializer." + suffix
            }
            return prefix + "the type's user `init(...)` declarations don't "
                + "support derivation — no non-failable, non-throwing "
                + "initializer (with 1–\(memberwiseArityLimit) parameters) has "
                + "all parameter types resolve to a recognized generator." + suffix
        }
        if shape.storedMembers.count > memberwiseArityLimit {
            return prefix + "the type has \(shape.storedMembers.count) stored "
                + "properties; memberwise derivation supports up to "
                + "\(memberwiseArityLimit) (the upstream `zip` arity limit)."
                + suffix
        }
        if let unknown = shape.storedMembers.first(where: {
            RawType(typeName: $0.typeName) == nil
                && memberGenerator(forTypeName: $0.typeName) == nil
        }) {
            return prefix + "stored property `\(unknown.name): "
                + "\(unknown.typeName)` has no recognized stdlib raw type "
                + "(memberwise derivation supports Int/String/Bool/Double/"
                + "Float, the fixed-width integer family, Character, and Date, "
                + "plus optionals, arrays, sets, and dictionaries of those)." + suffix
        }
        return prefix + "memberwise derivation didn't apply." + suffix
    }
}
