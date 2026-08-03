import SwiftSyntax

/// Detects that an initializer states a **precondition** on its arguments.
///
/// A derived generator draws arbitrary values. When the initializer it calls asserts
/// something about them, those values are not merely unusual — the type has said they are
/// invalid, and calling it aborts the process.
///
/// **Measured 2026-08-02 on swift-collections.** Three carriers took down the whole generated
/// suite, each on the same shape:
///
/// ```swift
/// init(at position: Int) { assert(position >= 0); … }   // _DequeSlot
/// init(offset: Int, level: Int) { assert(offset >= 0); … }  // _HeapNode
/// init(offset: Int) { assert(offset >= 0); … }          // _HashTable.Bucket
/// ```
///
/// **This declines rather than trying to satisfy the condition**, which is the same choice
/// `capacityHintLabels` makes and for a stronger reason. Parsing `assert(position >= 0)` into
/// a bound is possible for that one comparison and hopeless in general —
/// `assert(level == Self.level(forOffset: offset))`, on the very next line of `_HeapNode`, is
/// a relationship between two parameters computed by a static method. A tool that satisfied
/// the easy conditions and silently ignored the hard ones would generate values that pass the
/// assertion it understood and violate the one it did not.
///
/// The carrier falls to `.todo`, whose message asks for a hand-written `gen()`. That is the
/// honest answer: the invariant is knowable by the type's author and not by this tool.
///
/// **The evidence is the body, not the name.** `capacityHintLabels` has to guess from
/// `minimumCapacity` because a capacity hint looks like any other `Int`. Here the type says
/// so out loud, which makes this the more reliable of the two gates.
public enum InitializerPreconditionDetector {

    /// Functions whose presence in an initializer body means "these arguments must satisfy
    /// something". `fatalError` is deliberately absent: it marks an unreachable path or an
    /// unimplemented stub, not a constraint on arguments.
    public static let preconditionFunctions: Set<String> = [
        "assert", "precondition", "assertionFailure", "preconditionFailure"
    ]

    /// `true` when the initializer's body calls one of `preconditionFunctions`.
    ///
    /// Walks all descendants, so a call guarded by `#if COLLECTIONS_INTERNAL_CHECKS` still
    /// counts — a debug-only assertion is still a statement that the argument is invalid, and
    /// the generated suite is itself built in debug.
    public static func statesPrecondition(_ initializer: InitializerDeclSyntax) -> Bool {
        guard let body = initializer.body else { return false }
        return containsPreconditionCall(Syntax(body))
    }

    /// `true` when the body delegates with `self.init(…)`.
    ///
    /// **`_HeapNode` is why this exists.** Its `init(offset:)` asserts nothing and looks
    /// derivable; its body is `self.init(offset: offset, level: Self.level(forOffset: offset))`
    /// and *that* initializer asserts `offset >= 0`. The precondition is one hop away, so a
    /// body-only check declares the type safe and the generated suite still aborts.
    ///
    /// Recorded rather than resolved: matching the call to a specific overload would mean
    /// implementing overload resolution. The strategist pairs this with "does any initializer
    /// on this type assert", which is conservative in the right direction — it can decline a
    /// delegation to a clean sibling, and cannot admit one to a dirty sibling.
    public static func delegatesToSelf(_ initializer: InitializerDeclSyntax) -> Bool {
        guard let body = initializer.body else { return false }
        return containsSelfInitCall(Syntax(body))
    }

    private static func containsSelfInitCall(_ node: Syntax) -> Bool {
        if let call = node.as(FunctionCallExprSyntax.self),
           let member = call.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "init" {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate) where containsSelfInitCall(child) {
            return true
        }
        return false
    }

    private static func containsPreconditionCall(_ node: Syntax) -> Bool {
        if let call = node.as(FunctionCallExprSyntax.self),
           let callee = call.calledExpression.as(DeclReferenceExprSyntax.self),
           preconditionFunctions.contains(callee.baseName.text) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate) where containsPreconditionCall(child) {
            return true
        }
        return false
    }
}
