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
/// **The standard library's refinements seed it too.** Seeding with `Sendable`
/// alone treated a type whose only route to it is `Error` as not `Sendable`.
/// Measured 2026-10-29 by rescanning the PRD §8 Pass 1 packages: **11 of the 44
/// types skipped as "`public` without `Sendable`" were Sendable after all**:
/// `ArgumentParser.ExitCode: Error, RawRepresentable, Hashable` and seven other
/// error types, a `Clock` and its `InstantProtocol` instant, and an actor. A
/// module cannot redeclare the standard library, so that part of the "other
/// module" blind spot is a fixed list rather than a limit of syntax. Foundation
/// is seeded the same way, because it ships no sources either.
///
/// **A third-party protocol is seen when its source is.** The discovery plugin
/// passes every SwiftPM dependency's sources as context files, and they are
/// parsed here with the target's. Measured on the same packages with their
/// dependencies as context: Hummingbird's `Application`, `Sendable` through
/// swift-service-lifecycle's `Service`, stops being skipped, and every skip
/// left is a type that really is not `Sendable`. What stays invisible is a
/// module with no sources, an SDK framework other than Foundation or a binary
/// target, so a type conforming only to one of its protocols remains a false
/// positive.
enum SendableProtocols {

    /// The public protocols of `Swift` and `_Concurrency`, the two modules every
    /// file imports implicitly, that refine `Sendable`, directly or through one
    /// another. Read from the macOS 27.0 SDK's `.swiftinterface` files as a
    /// fixed point over all 112 protocol declarations in them, not written from
    /// memory. `SerialExecutor` and `TaskExecutor` reach `Sendable` through
    /// `Executor`. `UnsafeSendable` is deprecated but still public.
    /// `SendableMetatype` is not here: `Sendable` refines it, not the reverse.
    static let standardLibraryRefinements: Set<String> = [
        "Actor", "Clock", "CodingKey", "DurationProtocol", "Error", "Executor",
        "InstantProtocol", "SerialExecutor", "TaskExecutor", "UnsafeSendable"
    ]

    /// Foundation's public protocols that refine `Sendable`, read the same way
    /// from its `.swiftinterface` (40 protocol declarations, closed over the
    /// standard library's). Foundation ships no sources, so the discovery
    /// plugin's context files cannot supply these, and `struct AppError:
    /// LocalizedError` is common in exactly the code the plugin scans. The
    /// first three reach `Sendable` through `Error`. `AsyncMessage` is nested
    /// in `NotificationCenter` and seeded under the name a conformance spells.
    /// Other SDK frameworks are left out: SwiftUI's and Distributed's
    /// refinements are adopted by views, documents and distributed actors,
    /// which have no laws to check, and an actor is `Sendable` already.
    static let foundationRefinements: Set<String> = [
        "CustomNSError", "LocalizedError", "RecoverableError",
        "AttributedStringProtocol", "NotificationCenter.AsyncMessage",
        "SortComparator", "StandardPredicateExpression"
    ]

    /// Names of protocols that refine `Sendable`, including `Sendable` itself
    /// and its `@unchecked` spelling.
    static func refining(in files: [SourceFileSyntax]) -> Set<String> {
        var inherits: [String: [String]] = [:]
        for file in files {
            collect(from: file.statements.map(\.item), into: &inherits)
        }
        // A module's own protocol shadows a standard-library one of the same
        // name, so a seed the module redeclares is judged by the module's
        // inheritance clause instead, like any other protocol it declares.
        var sendable = standardLibraryRefinements
            .union(foundationRefinements)
            .subtracting(inherits.keys)
            .union(["Sendable"])
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

    /// `@unchecked Sendable`, `any Sendable` and `Swift.Sendable` reduce to
    /// `Sendable`; generic arguments and whitespace are dropped so `Foo<Bar>`
    /// compares as `Foo`. Only the seeded modules' qualifiers are stripped:
    /// Hummingbird spells one conformance `Swift.Error` because it declares a
    /// type named `Error` of its own.
    static func normalized(_ name: String) -> String {
        var text = name
        for prefix in ["@unchecked ", "@retroactive ", "any ", "some ", "Swift.", "_Concurrency.", "Foundation."] {
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
