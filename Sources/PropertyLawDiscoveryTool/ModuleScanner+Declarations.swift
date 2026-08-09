import PropertyLawCore
import PropertyLawSyntaxSupport
import SwiftSyntax

/// The syntax-walking half of `ModuleScanner`: turning declarations into
/// `TypeAggregate` records, including the descent into nested types.
///
/// Split from `ModuleScanner.swift` to keep that file under the 400-line lint,
/// following the `ModuleScanner+Shapes.swift` precedent.
extension ModuleScanner {

    /// Records `statement`, then **descends into it**.
    ///
    /// **The scanner used to walk top-level statements only**, so a type
    /// declared inside another type — or inside an `extension`, which is how
    /// swift-collections writes most of its views — was never seen as a primary
    /// declaration. It entered the map solely through
    /// `extension BitSet.Counted: …`, with no stored members, no initializers
    /// and no kind, which pinned it at `.todo` no matter how derivable it was.
    ///
    /// **And the name it entered under was wrong.** `topLevelExtendedTypeName`
    /// kept only the last component, so `Counted` went out as
    /// `for: Counted.self` — a name that does not exist at module scope.
    /// Measured across swift-collections + swift-numerics +
    /// swift-async-algorithms: 13 of the 23 types with an emitted `.todo`
    /// generator were nested, and every one of them was emitted unqualified.
    ///
    /// `namespace` is the enclosing type path, so a nested declaration is
    /// recorded as `BitSet.Counted`. That is the spelling `GeneratorResolver`'s
    /// header already asked callers for — *"callers that scan nested types
    /// should record and reference them by qualified name"* — and it is what
    /// makes the emitted reference compile.
    static func accumulate(
        statement: CodeBlockItemSyntax.Item,
        context: RecordingContext,
        namespace: [String] = [],
        into perType: inout [String: TypeAggregate]
    ) {
        if let primary = primaryDecl(from: statement) {
            let qualified = (namespace + [primary.name]).joined(separator: ".")
            record(
                RecordRequest(
                    name: qualified,
                    accessLevel: primary.accessLevel,
                    inheritance: primary.inheritance,
                    node: primary.node,
                    kind: .primary,
                    typeKind: primary.kind,
                    hasUserGen: primary.hasUserGen,
                    storedMembers: primary.storedMembers,
                    hasUserInit: primary.hasUserInit,
                    initializers: primary.initializers,
                    enumCases: primary.enumCases,
                    witnesses: primary.witnesses,
                    memberFunctions: primary.memberFunctions
                ),
                context: context,
                into: &perType
            )
            descend(
                into: primary.memberBlock,
                context: context,
                namespace: namespace + [primary.name],
                into: &perType
            )
            return
        }
        guard let extensionDecl = statement.as(ExtensionDeclSyntax.self) else { return }
        accumulateExtension(
            extensionDecl, context: context, namespace: namespace, into: &perType
        )
    }

    /// The `extension` half of `accumulate`.
    ///
    /// Conditional conformances (`extension Foo: Equatable where T: ...`) are
    /// skipped as *conformances* — they're not unconditional, so emitting an
    /// unconditional check would be wrong (PRD §4.4 handles the bound case via
    /// an explicit `@LawGenerator(bindings:)`). The **body is still walked**: a
    /// `where` clause says nothing about the types declared inside the
    /// extension, and skipping them would lose the very nested declarations
    /// this pass exists to find.
    private static func accumulateExtension(
        _ extensionDecl: ExtensionDeclSyntax,
        context: RecordingContext,
        namespace: [String],
        into perType: inout [String: TypeAggregate]
    ) {
        let extensionNamespace = namespace + [extensionDecl.extendedType.trimmedDescription]
        defer {
            descend(
                into: extensionDecl.memberBlock,
                context: context,
                namespace: extensionNamespace,
                into: &perType
            )
        }
        guard extensionDecl.genericWhereClause == nil else { return }
        record(
            RecordRequest(
                name: extensionNamespace.joined(separator: "."),
                // An extension never restates the type's access level; leaving
                // this `.implicit` keeps the primary decl's reading authoritative.
                accessLevel: .implicit,
                inheritance: extensionDecl.inheritanceClause,
                node: Syntax(extensionDecl),
                kind: .extension,
                typeKind: nil,  // extension doesn't redefine the type kind
                hasUserGen: hasGenMethod(in: extensionDecl.memberBlock),
                // Extensions can't add stored properties or suppress the
                // synthesized memberwise init — both stay empty/false here.
                storedMembers: [],
                hasUserInit: false,
                initializers: [],
                enumCases: [],
                witnesses: WitnessFinder.find(in: extensionDecl.memberBlock),
                memberFunctions: RoundTripFinder.findMembers(in: extensionDecl.memberBlock)
            ),
            context: context,
            into: &perType
        )
    }

    /// Walks a member block for nested type declarations, under `namespace`.
    private static func descend(
        into memberBlock: MemberBlockSyntax,
        context: RecordingContext,
        namespace: [String],
        into perType: inout [String: TypeAggregate]
    ) {
        for member in memberBlock.members {
            guard let item = CodeBlockItemSyntax.Item(member.decl) else { continue }
            accumulate(
                statement: item,
                context: context,
                namespace: namespace,
                into: &perType
            )
        }
    }

    /// Unifies the four type-decl shapes a peer macro / scanner can see —
    /// keeps `accumulate` free of repeated `if let` ladders.
    private struct PrimaryDecl {
        let name: String
        let kind: TypeShape.Kind
        let accessLevel: AccessLevel
        /// Retained so `accumulate` can descend for nested declarations.
        let memberBlock: MemberBlockSyntax
        let inheritance: InheritanceClauseSyntax?
        let node: Syntax
        let hasUserGen: Bool
        let storedMembers: [StoredMember]
        let hasUserInit: Bool
        let initializers: [InitializerSignature]
        let enumCases: [EnumCase]
        let witnesses: WitnessSet
        let memberFunctions: [FunctionSignature]
    }

    private static func primaryDecl(
        from statement: CodeBlockItemSyntax.Item
    ) -> PrimaryDecl? {
        if let decl = statement.as(StructDeclSyntax.self) {
            return makePrimaryDecl(decl, kind: .struct)
        }
        if let decl = statement.as(ClassDeclSyntax.self) {
            return makePrimaryDecl(decl, kind: .class)
        }
        if let decl = statement.as(EnumDeclSyntax.self) {
            return makePrimaryDecl(decl, kind: .enum)
        }
        if let decl = statement.as(ActorDeclSyntax.self) {
            return makePrimaryDecl(decl, kind: .actor)
        }
        return nil
    }

    /// Single funnel that builds a `PrimaryDecl` from any of the four
    /// type-decl shapes — keeps the per-kind branches above small and
    /// makes the stored-member / user-init scan rules visible in one
    /// place. Stored members and user-init detection are gated on
    /// `kind == .struct` because PRD §5.7 Strategy 3 supports structs
    /// only.
    ///
    /// Takes the declaration itself rather than six unpacked fields: every
    /// caller was destructuring the same node the same way, and `kind` is the
    /// only thing the syntax tree can't supply (the four decl types share no
    /// protocol that names them). `DeclGroupSyntax` carries `modifiers`,
    /// `inheritanceClause` and `memberBlock`; `NamedDeclSyntax` carries `name`.
    /// Reading the modifiers through `MemberBlockInspector` rather than a local
    /// copy keeps type access and member access on one rule.
    private static func makePrimaryDecl(
        _ decl: some DeclGroupSyntax & NamedDeclSyntax,
        kind: TypeShape.Kind
    ) -> PrimaryDecl {
        let memberBlock = decl.memberBlock
        return PrimaryDecl(
            name: decl.name.text,
            kind: kind,
            accessLevel: MemberBlockInspector.accessLevel(of: decl.modifiers),
            memberBlock: memberBlock,
            inheritance: decl.inheritanceClause,
            node: Syntax(decl),
            hasUserGen: hasGenMethod(in: memberBlock),
            storedMembers: kind == .struct
                ? MemberBlockInspector.storedMembers(in: memberBlock)
                : [],
            hasUserInit: kind == .struct
                ? MemberBlockInspector.hasUserInit(in: memberBlock)
                : false,
            initializers: kind == .struct
                ? MemberBlockInspector.initializers(in: memberBlock)
                : [],
            enumCases: kind == .enum
                ? MemberBlockInspector.enumCases(in: memberBlock)
                : [],
            witnesses: WitnessFinder.find(in: memberBlock),
            memberFunctions: RoundTripFinder.findMembers(in: memberBlock)
        )
    }
}
