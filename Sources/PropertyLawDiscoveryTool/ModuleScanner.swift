import Foundation
import PropertyLawCore
import PropertyLawSyntaxSupport
import SwiftSyntax
import SwiftParser

// One private struct + one private static helper per syntactic concern
// the scanner aggregates (inheritance, gen detection, witnesses, member
// functions, stored members, user inits) — the enum body grows linearly
// with the discovery feature surface. Disable is paired with an explicit
// re-enable at end of file.
// swiftlint:disable type_body_length

/// Walks every `.swift` file in a target and aggregates type declarations
/// + their inheritance clauses (including extensions in other files) into
/// a single `ConformanceMap`.
///
/// Per-file errors are collected (file unreadable, etc.) rather than fatal
/// — the user gets a partial map plus a `parseFailures` list the emitter
/// can surface in the generated header.
enum ModuleScanner {

    static func scan(sourceFiles: [String]) -> ConformanceMap {
        var perType: [String: TypeAggregate] = [:]
        var failures: [ConformanceMap.ParseFailure] = []
        var topLevelFunctions: [FunctionSignature] = []

        // Sorted input → sorted scan order → deterministic output.
        for filePath in sourceFiles.sorted() {
            let source: String
            do {
                source = try String(contentsOfFile: filePath, encoding: .utf8)
            } catch {
                failures.append(ConformanceMap.ParseFailure(
                    filePath: filePath,
                    message: "could not read file: \(error.localizedDescription)"
                ))
                continue
            }
            let parsed = Parser.parse(source: source)
            let converter = SourceLocationConverter(fileName: filePath, tree: parsed)
            // M5 module-scope round-trip discovery — collect top-level
            // free functions across files for the suggester's module
            // pairing pass.
            topLevelFunctions.append(contentsOf: RoundTripFinder.findTopLevel(in: parsed))
            for statement in parsed.statements {
                accumulate(
                    statement: statement.item,
                    context: RecordingContext(filePath: filePath, converter: converter),
                    into: &perType
                )
            }
        }
        return ConformanceMap(
            entries: makeEntries(from: perType),
            parseFailures: failures,
            witnesses: makeWitnesses(from: perType),
            memberFunctions: makeMemberFunctions(from: perType),
            topLevelFunctions: topLevelFunctions
        )
    }

    private static func makeWitnesses(
        from perType: [String: TypeAggregate]
    ) -> [String: WitnessSet] {
        var result: [String: WitnessSet] = [:]
        for (name, aggregate) in perType where aggregate.witnesses != WitnessSet() {
            result[name] = aggregate.witnesses
        }
        return result
    }

    private static func makeMemberFunctions(
        from perType: [String: TypeAggregate]
    ) -> [String: [FunctionSignature]] {
        var result: [String: [FunctionSignature]] = [:]
        for (name, aggregate) in perType where !aggregate.memberFunctions.isEmpty {
            result[name] = aggregate.memberFunctions
        }
        return result
    }

    /// Per-type aggregator — collects inheritance names + provenance
    /// records + decl-kind + gen() presence + witness signatures across
    /// primary decl and any extensions seen in any file.
    private struct TypeAggregate {
        var inheritedNames: [String] = []
        var provenances: [ConformanceMap.Provenance] = []
        /// First primary-decl kind we encountered for this type. Stays
        /// `nil` if only extensions were seen (rare; extensions of types
        /// declared in other modules).
        var typeKind: TypeShape.Kind?
        var hasUserGen: Bool = false
        /// Stored properties from the primary decl (extensions can't
        /// add stored properties in Swift, so only the primary decl
        /// contributes). Stays empty when only extensions are seen.
        var storedMembers: [StoredMember] = []
        /// `true` if the primary decl's body contains any `init(...)`.
        /// PRD §5.7 Strategy 3 falls through when this is set, since
        /// Swift suppresses the synthesized memberwise init.
        var hasUserInit: Bool = false
        /// Initializer signatures from the primary decl, for the Tier 6
        /// `initializerBased` strategy. Empty unless a primary struct decl
        /// contributed them.
        var initializers: [InitializerSignature] = []
        /// Element-wise OR of witnesses seen in primary decl + every
        /// extension. PRD §5.4 advisory suggestions read from here.
        var witnesses: WitnessSet = WitnessSet()
        /// Concatenation of member function signatures seen across the
        /// primary decl and every extension. Order is the scan order
        /// (file path ascending, declaration order within each file)
        /// so output stays deterministic. PRD §5.5 round-trip
        /// suggestions read from here.
        var memberFunctions: [FunctionSignature] = []
    }

    /// Bundles file-level scanning context so `recordType` stays under
    /// the function-parameter-count lint.
    private struct RecordingContext {
        let filePath: String
        let converter: SourceLocationConverter
    }

    private static func makeEntries(
        from perType: [String: TypeAggregate]
    ) -> [ConformanceMap.Entry] {
        // Build the whole-module type universe once so nested custom-type
        // members/parameters resolve (Tier 3). Every scanned type is included
        // — even non-conformance-bearing helper types — so a referenced type
        // still resolves when it isn't itself a test target.
        let shapesByName = makeShapes(from: perType)
        let resolver = GeneratorResolver(types: Array(shapesByName.values))
        return perType.keys.sorted().map { typeName -> ConformanceMap.Entry in
            let aggregate = perType[typeName]!
            let raw = KnownProtocol.set(from: aggregate.inheritedNames)
            let shape = shapesByName[typeName]!
            return ConformanceMap.Entry(
                typeName: typeName,
                conformances: KnownProtocol.mostSpecific(
                    in: raw.subtracting(KnownProtocol.unemittable)
                ),
                provenances: aggregate.provenances.sorted(),
                derivationStrategy: DerivationStrategist.strategy(
                    for: shape,
                    resolve: resolver.customTypeGenerator
                )
            )
        }
    }

    /// One `TypeShape` per scanned type. `.struct` is the default kind when
    /// only extensions were seen (the strategist falls through to `.todo`
    /// anyway in that case).
    private static func makeShapes(
        from perType: [String: TypeAggregate]
    ) -> [String: TypeShape] {
        var shapes: [String: TypeShape] = [:]
        for (typeName, aggregate) in perType {
            shapes[typeName] = TypeShape(
                name: typeName,
                kind: aggregate.typeKind ?? .struct,
                inheritedTypes: aggregate.inheritedNames,
                hasUserGen: aggregate.hasUserGen,
                storedMembers: aggregate.storedMembers,
                hasUserInit: aggregate.hasUserInit,
                initializers: aggregate.initializers
            )
        }
        return shapes
    }

    private static func accumulate(
        statement: CodeBlockItemSyntax.Item,
        context: RecordingContext,
        into perType: inout [String: TypeAggregate]
    ) {
        if let primary = primaryDecl(from: statement) {
            record(
                RecordRequest(
                    name: primary.name,
                    inheritance: primary.inheritance,
                    node: primary.node,
                    kind: .primary,
                    typeKind: primary.kind,
                    hasUserGen: primary.hasUserGen,
                    storedMembers: primary.storedMembers,
                    hasUserInit: primary.hasUserInit,
                    initializers: primary.initializers,
                    witnesses: primary.witnesses,
                    memberFunctions: primary.memberFunctions
                ),
                context: context,
                into: &perType
            )
            return
        }
        guard let extensionDecl = statement.as(ExtensionDeclSyntax.self) else { return }
        // Skip conditional conformances (`extension Foo: Equatable where T: ...`)
        // — they're not unconditional, so emitting an unconditional check
        // would be wrong. PRD §4.4 generic conformances handle the bound
        // case via an explicit @LawGenerator(bindings:) annotation, M3 scope.
        guard extensionDecl.genericWhereClause == nil else { return }
        guard let typeName = topLevelExtendedTypeName(of: extensionDecl) else { return }
        record(
            RecordRequest(
                name: typeName,
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
                witnesses: WitnessFinder.find(in: extensionDecl.memberBlock),
                memberFunctions: RoundTripFinder.findMembers(in: extensionDecl.memberBlock)
            ),
            context: context,
            into: &perType
        )
    }

    /// Unifies the four type-decl shapes a peer macro / scanner can see —
    /// keeps `accumulate` free of repeated `if let` ladders.
    private struct PrimaryDecl {
        let name: String
        let kind: TypeShape.Kind
        let inheritance: InheritanceClauseSyntax?
        let node: Syntax
        let hasUserGen: Bool
        let storedMembers: [StoredMember]
        let hasUserInit: Bool
        let initializers: [InitializerSignature]
        let witnesses: WitnessSet
        let memberFunctions: [FunctionSignature]
    }

    private static func primaryDecl(
        from statement: CodeBlockItemSyntax.Item
    ) -> PrimaryDecl? {
        if let decl = statement.as(StructDeclSyntax.self) {
            return makePrimaryDecl(
                name: decl.name.text,
                kind: .struct,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                memberBlock: decl.memberBlock
            )
        }
        if let decl = statement.as(ClassDeclSyntax.self) {
            return makePrimaryDecl(
                name: decl.name.text,
                kind: .class,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                memberBlock: decl.memberBlock
            )
        }
        if let decl = statement.as(EnumDeclSyntax.self) {
            return makePrimaryDecl(
                name: decl.name.text,
                kind: .enum,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                memberBlock: decl.memberBlock
            )
        }
        if let decl = statement.as(ActorDeclSyntax.self) {
            return makePrimaryDecl(
                name: decl.name.text,
                kind: .actor,
                inheritance: decl.inheritanceClause,
                node: Syntax(decl),
                memberBlock: decl.memberBlock
            )
        }
        return nil
    }

    /// Single funnel that builds a `PrimaryDecl` from any of the four
    /// type-decl shapes — keeps the per-kind branches above small and
    /// makes the stored-member / user-init scan rules visible in one
    /// place. Stored members and user-init detection are gated on
    /// `kind == .struct` because PRD §5.7 Strategy 3 supports structs
    /// only.
    private static func makePrimaryDecl(
        name: String,
        kind: TypeShape.Kind,
        inheritance: InheritanceClauseSyntax?,
        node: Syntax,
        memberBlock: MemberBlockSyntax
    ) -> PrimaryDecl {
        PrimaryDecl(
            name: name,
            kind: kind,
            inheritance: inheritance,
            node: node,
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
            witnesses: WitnessFinder.find(in: memberBlock),
            memberFunctions: RoundTripFinder.findMembers(in: memberBlock)
        )
    }

    /// True when `memberBlock` declares a `static func gen()` method.
    /// The plugin sees the whole module so this catches gen() defined in
    /// the primary body OR in any extension.
    private static func hasGenMethod(in memberBlock: MemberBlockSyntax) -> Bool {
        for member in memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard funcDecl.name.text == "gen" else { continue }
            let isStatic = funcDecl.modifiers.contains { mod in
                mod.name.tokenKind == .keyword(.static)
            }
            if isStatic { return true }
        }
        return false
    }

    /// Single-record-call payload — keeps `record` under the
    /// function-parameter-count lint.
    private struct RecordRequest {
        let name: String
        let inheritance: InheritanceClauseSyntax?
        let node: Syntax
        let kind: ConformanceMap.ProvenanceKind
        let typeKind: TypeShape.Kind?
        let hasUserGen: Bool
        let storedMembers: [StoredMember]
        let hasUserInit: Bool
        let initializers: [InitializerSignature]
        let witnesses: WitnessSet
        let memberFunctions: [FunctionSignature]
    }

    private static func record(
        _ request: RecordRequest,
        context: RecordingContext,
        into perType: inout [String: TypeAggregate]
    ) {
        var aggregate = perType[request.name] ?? TypeAggregate()
        if let inheritance = request.inheritance {
            for inheritedType in inheritance.inheritedTypes {
                aggregate.inheritedNames.append(inheritedType.type.trimmedDescription)
            }
        }
        let location = request.node.startLocation(converter: context.converter)
        aggregate.provenances.append(ConformanceMap.Provenance(
            filePath: context.filePath,
            line: location.line,
            kind: request.kind
        ))
        // Set typeKind from the primary decl, never from an extension.
        if let primaryKind = request.typeKind {
            aggregate.typeKind = primaryKind
        }
        // hasUserGen latches once true — gen() seen anywhere wins.
        if request.hasUserGen { aggregate.hasUserGen = true }
        // Stored members & user-init come from the primary decl only;
        // extensions pass empty/false so the OR-combine below is a no-op.
        if !request.storedMembers.isEmpty {
            aggregate.storedMembers = request.storedMembers
        }
        if request.hasUserInit { aggregate.hasUserInit = true }
        // Initializers come from the primary decl only (extensions pass []).
        if !request.initializers.isEmpty {
            aggregate.initializers = request.initializers
        }
        aggregate.witnesses.merge(request.witnesses)
        aggregate.memberFunctions.append(contentsOf: request.memberFunctions)
        perType[request.name] = aggregate
    }

    /// Extension extends `Foo` or `Module.Foo` — return the leaf identifier.
    /// Nested-type extensions (`extension Outer.Inner`) are M2+ scope.
    private static func topLevelExtendedTypeName(of extensionDecl: ExtensionDeclSyntax) -> String? {
        let typeText = extensionDecl.extendedType.trimmedDescription
        return typeText.split(separator: ".").last.map(String.init)
    }
}

// swiftlint:enable type_body_length
