import SwiftSyntax

/// Which protocols in the scanned module (transitively) refine `Sendable`.
///
/// **Measured 2026-08-08 on swift-syntax, and it invalidated the first version
/// of the `Sendable` skip rule.** That rule looked for the literal string
/// `Sendable` in a type's own inheritance clause, and documented its own
/// blind spot: *"a type made Sendable by … an inherited protocol that itself
/// refines Sendable"*. `SwiftSyntax` is exactly that shape —
/// `public protocol SyntaxProtocol: …, Sendable` with every node declared
/// `public struct AccessorBlockSyntax: SyntaxProtocol, SyntaxHashable` — so the
/// rule skipped **673 types in one module**, every one of them a false
/// positive. A documented limitation at that scale is not a limitation, it is
/// the rule not working.
///
/// The fix is a fixed point over the module's own protocol declarations:
/// `Sendable` seeds the set, and any protocol inheriting something already in
/// it joins. Two passes would miss a three-deep chain, so it iterates to
/// convergence.
///
/// **Still syntactic, and still one-module.** A protocol declared in *another*
/// module that refines `Sendable` is invisible here, so a type conforming only
/// to that remains a false positive. That residue is small and, unlike the
/// original, does not describe an entire library's node hierarchy.
enum SendableProtocols {

    /// Names of protocols that refine `Sendable`, including `Sendable` itself
    /// and its `@unchecked` spelling.
    static func refining(in files: [SourceFileSyntax]) -> Set<String> {
        var inherits: [String: [String]] = [:]
        for file in files {
            collect(from: file.statements.map(\.item), into: &inherits)
        }
        var sendable: Set<String> = ["Sendable"]
        var changed = true
        while changed {
            changed = false
            for (name, parents) in inherits where !sendable.contains(name) {
                if parents.contains(where: { sendable.contains(normalized($0)) }) {
                    sendable.insert(name)
                    changed = true
                }
            }
        }
        return sendable
    }

    /// Whether any of `inheritedNames` supplies `Sendable`, given the module's
    /// refining set. Matches the bare and `@unchecked` spellings directly so a
    /// caller needs no special case for either.
    static func satisfiesSendable(
        inheritedNames: [String],
        refining: Set<String>
    ) -> Bool {
        inheritedNames.contains { refining.contains(normalized($0)) }
    }

    /// `@unchecked Sendable` and `any Sendable` reduce to `Sendable`; generic
    /// arguments and whitespace are dropped so `Foo<Bar>` compares as `Foo`.
    private static func normalized(_ name: String) -> String {
        var text = name
        for prefix in ["@unchecked ", "@retroactive ", "any ", "some "] {
            while text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        }
        if let angle = text.firstIndex(of: "<") { text = String(text[text.startIndex ..< angle]) }
        return text.trimmingCharacters(in: [" "])
    }

    /// Protocol declarations at any nesting depth — a protocol nested in a type
    /// is unusual but costs nothing to walk, and missing one would silently
    /// reintroduce the false positives this exists to remove.
    private static func collect(
        from items: [CodeBlockItemSyntax.Item],
        into inherits: inout [String: [String]]
    ) {
        for item in items {
            if let proto = item.as(ProtocolDeclSyntax.self) {
                inherits[proto.name.text] = (proto.inheritanceClause?.inheritedTypes ?? [])
                    .map { $0.type.trimmedDescription }
                collect(from: members(of: proto.memberBlock), into: &inherits)
                continue
            }
            guard let group = item.as(DeclSyntax.self)?.asProtocol(DeclGroupSyntax.self) else {
                continue
            }
            collect(from: members(of: group.memberBlock), into: &inherits)
        }
    }

    private static func members(of block: MemberBlockSyntax) -> [CodeBlockItemSyntax.Item] {
        block.members.compactMap { CodeBlockItemSyntax.Item($0.decl) }
    }
}
