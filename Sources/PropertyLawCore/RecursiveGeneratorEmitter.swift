/// Emits the depth-budgeted `func` that generates a **self-referential** type.
///
/// ## Why a function, when everything else is inlined
///
/// `GeneratorResolver`'s contract is that a nested custom type is *inlined* —
/// the emitted stub is self-contained and needs no generated `gen()` methods.
/// Recursion is the one shape where that is impossible: an expression cannot
/// contain itself. So a recursive type gets a named helper, the plan renders as
/// a call to it, and `GeneratorPlan.supportingDeclarations` carries the `func`
/// up to whoever writes the stub.
///
/// ## The shape, and the trap that dictates it
///
/// ```swift
/// func __genDirectoryNode(_ budget: Int) -> Generator<DirectoryNode, AnySequence<Any>> {
///     if budget <= 0 {
///         return zip(…, Gen<[DirectoryNode]>.always([]))   // base: recursion collapsed
///             .map { DirectoryNode(name: $0, children: $1) }.eraseToAny()
///     }
///     return zip(…, __genDirectoryNode(budget - 1).array(of: 0...8))
///         .map { DirectoryNode(name: $0, children: $1) }.eraseToAny()
/// }
/// ```
///
/// The `if budget <= 0` must be a **real early return**, not a ternary inside
/// the expression. `Gen.array(of:)` evaluates its element generator eagerly, so
/// `.array(of: budget > 0 ? 0...8 : 0...0)` still constructs
/// `__genDirectoryNode(budget - 1)` in order to pass it — which constructs
/// `__genDirectoryNode(budget - 2)`, and so on past zero. That is an infinite
/// loop at generator-*construction* time, before a single value is drawn, and
/// it does not announce itself as a recursion bug: the stub simply hangs.
///
/// `eraseToAny()` on both arms is what makes the return type nameable.
/// `Generator` is generic over its shrink sequence as well as its value, and
/// the two arms have structurally different shrinkers, so without erasure the
/// function has no single spellable return type.
///
/// ## Scope, set by measurement
///
/// Only recursion that sits under a **collection or optional wrapper** is
/// emitted — `[Self]`, `Self?`, `Set<Self>`, `[K: Self]` — because the wrapper
/// is what supplies the base-case terminal (`[]`, `nil`). That is not a
/// convenient subset: a brace-matched scan of swift-foundation, swift-syntax,
/// swift-argument-parser/nio and SwiftProjectLint (~1,840 files) found exactly
/// two genuinely recursive data types, `DirectoryNode.children: [DirectoryNode]`
/// and `CommandInfoV0.subcommands: [CommandInfoV0]?`, and **both** are of this
/// shape. Zero self-referential `indirect enum`s.
///
/// A bare `case add(Expr, Expr)` payload has no wrapper to collapse, so its
/// base arm would have to be built from the type's non-recursive cases —
/// `EnumCaseEmitter`'s job, not this one. Those stay `.todo`, which is the same
/// answer as before rather than a regression.
public enum RecursiveGeneratorEmitter {

    /// The helper name for `typeName`. Double-underscored and type-qualified so
    /// it cannot collide with anything in the stub's scope or with a second
    /// recursive type in the same stub.
    public static func helperName(for typeName: String) -> String {
        "__gen" + typeName.split(separator: ".").joined()
    }

    /// Foundation-free `replacingOccurrences`. `PropertyLawCore` imports no
    /// Foundation on purpose — the module's zero-dependency footprint is a
    /// shipped property of the package, not an accident — so this walks the
    /// string directly rather than pulling the framework in for one call.
    static func replacing(_ needle: String, with replacement: String, in haystack: String) -> String {
        guard !needle.isEmpty else { return haystack }
        let needleChars = Array(needle)
        let chars = Array(haystack)
        var out = ""
        var index = 0
        while index < chars.count {
            if index + needleChars.count <= chars.count,
               Array(chars[index..<(index + needleChars.count)]) == needleChars {
                out += replacement
                index += needleChars.count
            } else {
                out.append(chars[index])
                index += 1
            }
        }
        return out
    }

    /// The call this type's recursion points render as, inside the helper body.
    public static func recursionPoint(for typeName: String) -> String {
        "\(helperName(for: typeName))(budget - 1)"
    }

    /// Whether `expression` refers back to `typeName` — i.e. the strategy
    /// resolved a member to this type's own recursion point.
    ///
    /// A string test rather than a walk over `GeneratorPlan`, because the plan
    /// tree does not survive the strategy layer: `MemberSpec.generatorExpression`
    /// is a `String`, so by the time `GeneratorResolver.derive` has a composed
    /// generator the structure has already been rendered. The marker is
    /// double-underscored and type-qualified precisely so this test cannot
    /// match anything a user wrote.
    public static func isRecursive(expression: String, typeName: String) -> Bool {
        expression.contains(recursionPoint(for: typeName))
    }

    /// The base arm: `expression` with every recursion point collapsed to the
    /// empty form its wrapper implies. `nil` when a recursion point survives
    /// the rewrite — a bare self-reference with no wrapper to terminate it,
    /// which stays `.todo` exactly as before.
    static func baseArm(expression: String, typeName: String) -> String? {
        let point = recursionPoint(for: typeName)
        var out = expression
        // Order matters: the longest wrapper suffix must be tried first, or
        // `.array(of: 0...8)` would be left dangling after a shorter match.
        let collapses: [(suffix: String, terminal: String)] = [
            (".array(of: 0...8).optional", "Gen<[\(typeName)]?>.always(nil)"),
            (".array(of: 0...8)", "Gen<[\(typeName)]>.always([])"),
            (".set(ofAtMost: 0...8)", "Gen<Set<\(typeName)>>.always([])"),
            (".optional", "Gen<\(typeName)?>.always(nil)")
        ]
        for (suffix, terminal) in collapses {
            out = replacing(point + suffix, with: terminal, in: out)
        }
        // A recursion point with no recognized wrapper cannot be terminated.
        guard !out.contains(point) else { return nil }
        return out
    }

    /// Build the `func` declaration, or `nil` when the recursion has no
    /// wrapper to terminate it (see the scope note above).
    ///
    /// - Parameters:
    ///   - typeName: the recursive type.
    ///   - expression: the type's own generator expression, in which its
    ///     recursion points have already been rendered as
    ///     `__genType(budget - 1)`.
    public static func declaration(
        typeName: String,
        expression: String
    ) -> String? {
        guard isRecursive(expression: expression, typeName: typeName),
              let base = baseArm(expression: expression, typeName: typeName) else {
            return nil
        }
        let name = helperName(for: typeName)
        return """
            /// Depth-budgeted generator for the recursive type `\(typeName)`.
            /// The budget bounds tree depth; at zero the self-referential slots
            /// yield their empty form so construction terminates.
            func \(name)(_ budget: Int) -> Generator<\(typeName), AnySequence<Any>> {
                if budget <= 0 {
                    return \(indented(base)).eraseToAny()
                }
                return \(indented(expression)).eraseToAny()
            }
            """
    }

    /// Re-indent a rendered expression to sit under `return ` inside the func.
    private static func indented(_ expression: String) -> String {
        expression
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { $0.offset == 0 ? String($0.element) : "        " + $0.element }
            .joined(separator: "\n")
    }
}
