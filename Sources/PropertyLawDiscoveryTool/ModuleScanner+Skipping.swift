import PropertyLawCore

/// Why a detected type gets no emitted suite.
///
/// Both reasons mean the same thing operationally — the generated file would
/// not compile — and both were invisible until `@testable import` landed. While
/// the file imported no module at all, every suite failed at "cannot find type
/// in scope", which masked every subtler reason behind it.
///
/// Split from `ModuleScanner.swift` to keep that file under the 400-line lint,
/// following the `ModuleScanner+Shapes.swift` precedent.
extension ModuleScanner {

    /// Types the generated file could not name even with `@testable import`.
    ///
    /// `@testable` promotes `internal` to public-within-the-test-module, which
    /// is why the emitter uses it and why `internal` types stay in the output.
    /// It does nothing for `private` / `fileprivate`, whose visibility is
    /// scoped to a declaration or a file rather than a module — a suite saying
    /// `for: Thing.self` would not compile. They are dropped and reported.
    ///
    /// **Extension-only types are deliberately kept.** A type seen only through
    /// `extension Foo: Equatable` has no primary decl here, so its level reads
    /// `.implicit` — the right answer, because the declaration lives in another
    /// module and is public enough to extend.
    ///
    /// Known limitation: nesting is not modelled. A `public struct Inner`
    /// declared inside a `private struct Outer` is unnameable too, and reads as
    /// `.public` here. The scanner records nested types under bare names
    /// already (see `GeneratorResolver`'s ambiguity handling), so fixing this
    /// means teaching it qualified names first.
    static func skippedTypes(
        in perType: [String: TypeAggregate],
        sendableProtocols: Set<String>
    ) -> [SkippedType] {
        perType.keys.sorted().compactMap { typeName in
            // Context-only types are not this target's to test or to report.
            guard perType[typeName]!.seenInTarget else { return nil }
            guard let reason = skipReason(
                for: perType[typeName]!, sendableProtocols: sendableProtocols
            ) else { return nil }
            return SkippedType(typeName: typeName, reason: reason)
        }
    }

    /// `nil` when a suite for this type would compile.
    static func skipReason(
        for aggregate: TypeAggregate,
        sendableProtocols: Set<String> = ["Sendable"]
    ) -> SkippedType.Reason? {
        if !aggregate.accessLevel.isCallable(from: .separateFile) {
            return .notNameable(aggregate.accessLevel)
        }
        // A foreign type is reachable only through a plain `import`. `@testable`
        // is emitted for the scanned target alone — across a package boundary it
        // is unreliable and, for a dependency built without testability, simply
        // absent — so `internal` in someone else's module is out of reach
        // however the imports are written. Without this the module-provenance
        // work would trade one uncompilable emission for another.
        if let module = aggregate.declaringModule,
           aggregate.accessLevel != .public, aggregate.accessLevel != .open {
            return .foreignNonPublic(module)
        }
        if requiresExplicitSendable(aggregate),
           !declaresSendable(aggregate, sendableProtocols) {
            return .notSendable
        }
        return nil
    }

    /// **Swift infers `Sendable` for non-public types only.** Every
    /// `check<Protocol>PropertyLaws` entry point is constrained
    /// `Value: … & Sendable`, so a `public struct Point: Hashable` with no
    /// explicit conformance fails to type-check at the call site — *"type
    /// 'PublicPoint' does not conform to the 'Sendable' protocol"*.
    ///
    /// This was invisible until `@testable import` landed: while the generated
    /// file named no types at all, nothing got far enough to be rejected for
    /// this. It showed up on the first suite that actually compiled.
    ///
    /// Verified against the compiler on 2026-08-08 with a two-target package:
    /// a `public struct` fails the cross-module `Sendable` requirement and a
    /// `package struct` satisfies it, so the rule stops at `public` / `open`.
    private static func requiresExplicitSendable(_ aggregate: TypeAggregate) -> Bool {
        aggregate.accessLevel == .public || aggregate.accessLevel == .open
    }

    /// Matched against the aggregated inheritance clauses — primary decl and
    /// every non-conditional extension, which is where a retroactive
    /// `extension Foo: Sendable {}` lands — using the module's set of
    /// `Sendable`-refining protocols rather than the literal string.
    ///
    /// **The literal-string version was measured wrong at scale.** On
    /// swift-syntax it skipped **673 types in one module**, every one a false
    /// positive: `SyntaxProtocol` refines `Sendable` and every node is declared
    /// `: SyntaxProtocol, SyntaxHashable`, never naming `Sendable` itself. See
    /// `SendableProtocols` for the fixed point that replaced it.
    ///
    /// **Residual false positive**, much smaller: a protocol declared in
    /// *another* module that refines `Sendable`, which a one-module syntactic
    /// scan cannot see. Such a type is reported as skipped when its suite would
    /// have compiled. That direction costs coverage; the other emits a file
    /// that doesn't build, taking the whole test target with it.
    private static func declaresSendable(
        _ aggregate: TypeAggregate,
        _ sendableProtocols: Set<String>
    ) -> Bool {
        SendableProtocols.satisfiesSendable(
            inheritedNames: aggregate.inheritedNames, refining: sendableProtocols
        )
    }
}
