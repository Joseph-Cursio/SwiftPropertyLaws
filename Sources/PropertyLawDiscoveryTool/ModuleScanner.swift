import Foundation
import PropertyLawCore
import PropertyLawSyntaxSupport
import SwiftSyntax
import SwiftParser

/// Walks every `.swift` file in a target and aggregates type declarations
/// + their inheritance clauses (including extensions in other files) into
/// a single `ConformanceMap`.
///
/// Per-file errors are collected (file unreadable, etc.) rather than fatal
/// — the user gets a partial map plus a `parseFailures` list the emitter
/// can surface in the generated header.
enum ModuleScanner {

    /// - Parameters:
    ///   - sourceFiles: the target's own sources. Types recorded from these get
    ///     an emitted suite.
    ///   - contextFiles: sources of the target's **dependencies**. Read for
    ///     declarations only — they enrich the resolver universe and tell the
    ///     diagnostics what a type actually is, but never produce a suite of
    ///     their own.
    ///
    /// **Why the split exists.** A per-target scan reaches types it can only see
    /// *extended*: `AccessorBlockSyntax` is declared in `SwiftSyntax` and
    /// extended in `SwiftParser`, so scanning `SwiftParser` alone knows nothing
    /// about it — no members, no initializers, not even its kind. Measured on
    /// swift-syntax: **114 of `SwiftParser`'s 199 detected types had no
    /// declaration in the target.** Handing the scan its dependencies' sources
    /// drops that to 46, and the rest are stdlib or out-of-scan modules.
    ///
    /// Merging the two lists into one would be the wrong fix: it also emits a
    /// suite for every dependency type, so `SwiftParser`'s generated file would
    /// carry 842 suites instead of 199 and duplicate every one that
    /// `SwiftSyntax`'s own run already emits. Context is for *knowing*, not for
    /// testing.
    static func scan(
        sourceFiles: [String],
        contextFiles: [String] = []
    ) -> ConformanceMap {
        var perType: [String: TypeAggregate] = [:]
        var failures: [ConformanceMap.ParseFailure] = []
        var topLevelFunctions: [FunctionSignature] = []
        var aliases: [String: String] = [:]
        var parsedFiles: [SourceFileSyntax] = []

        // Sorted input → sorted scan order → deterministic output. Context
        // files are walked first so a target extension always lands on an
        // aggregate that already knows the declaration.
        for file in orderedFiles(sourceFiles: sourceFiles, contextFiles: contextFiles) {
            let source: String
            do {
                source = try String(contentsOfFile: file.path, encoding: .utf8)
            } catch {
                failures.append(ConformanceMap.ParseFailure(
                    filePath: file.path,
                    message: "could not read file: \(error.localizedDescription)"
                ))
                continue
            }
            let parsed = Parser.parse(source: source)
            parsedFiles.append(parsed)
            topLevelFunctions.append(contentsOf: RoundTripFinder.findTopLevel(in: parsed))
            absorb(parsed, from: file, into: &perType, aliases: &aliases)
        }
        let shapes = makeShapes(from: perType)
        // Protocols that refine `Sendable`, so a type conforming to one of them
        // is not mistaken for a non-Sendable public type. See `SendableProtocols`.
        let sendableProtocols = SendableProtocols.refining(in: parsedFiles)
        return ConformanceMap(
            entries: makeEntries(
                from: perType, shapes: shapes, aliases: aliases,
                sendableProtocols: sendableProtocols
            ),
            parseFailures: failures,
            skippedTypes: skippedTypes(in: perType, sendableProtocols: sendableProtocols),
            witnesses: makeWitnesses(from: perType),
            memberFunctions: makeMemberFunctions(from: perType),
            topLevelFunctions: topLevelFunctions,
            shapesByName: shapes,
            aliases: aliases
        )
    }

    /// Walks one parsed file's top-level statements into the aggregate.
    private static func absorb(
        _ parsed: SourceFileSyntax,
        from file: ScannedFile,
        into perType: inout [String: TypeAggregate],
        aliases: inout [String: String]
    ) {
        let converter = SourceLocationConverter(fileName: file.path, tree: parsed)
        for statement in parsed.statements {
            if let alias = statement.item.as(TypeAliasDeclSyntax.self) {
                aliases[alias.name.text] = alias.initializer.value.trimmedDescription
            }
            accumulate(
                statement: statement.item,
                context: RecordingContext(
                    filePath: file.path,
                    converter: converter,
                    isContext: file.isContext,
                    moduleName: file.module
                ),
                into: &perType
            )
        }
    }

    /// Context first, then target sources — both sorted, so the scan order and
    /// therefore the output are deterministic.
    ///
    /// Context-first is load-bearing when a name is declared on both sides:
    /// `record` lets the last non-empty member list win, so target-last means
    /// the target's own declaration survives.
    static func orderedFiles(
        sourceFiles: [String],
        contextFiles: [String]
    ) -> [ScannedFile] {
        contextFiles.sorted().map(attributed)
            .map { ScannedFile(path: $0.path, module: $0.module, isContext: true) }
            + sourceFiles.sorted().map {
                ScannedFile(path: $0, module: nil, isContext: false)
            }
    }

    /// One file the scan will read, and what the scan knows about where it came
    /// from.
    struct ScannedFile {
        let path: String
        /// Module attributed by the caller (`Module=path`); `nil` for target
        /// files and unattributed context.
        let module: String?
        let isContext: Bool
    }

    /// Splits a `Module=path` context entry.
    ///
    /// A bare path (no `=`) is kept unattributed, so a caller that does not
    /// know or care which module a file belongs to keeps working. The split is
    /// on the **first** `=` and only when the left side looks like a module
    /// name — a path may legitimately contain `=`, and misreading one as a
    /// module would silently emit an import for a directory.
    static func attributed(_ entry: String) -> (path: String, module: String?) {
        guard let separator = entry.firstIndex(of: "=") else { return (entry, nil) }
        let candidate = String(entry[entry.startIndex ..< separator])
        let isModuleName = !candidate.isEmpty
            && !candidate.contains("/")
            && !candidate.contains(".")
        guard isModuleName else { return (entry, nil) }
        return (String(entry[entry.index(after: separator)...]), candidate)
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
    /// primary decl and any extensions seen in any file. Module-internal so
    /// `makeShapes` (in `ModuleScanner+Shapes.swift`) can consume it.
    struct TypeAggregate {
        var inheritedNames: [String] = []
        var provenances: [ConformanceMap.Provenance] = []
        /// First primary-decl kind we encountered for this type. Stays
        /// `nil` if only extensions were seen (rare; extensions of types
        /// declared in other modules).
        var typeKind: TypeShape.Kind?
        /// `true` once any *target* file declared or extended this type. Only
        /// these become emitted entries; a type known solely from context is
        /// somebody else's to test.
        var seenInTarget: Bool = false
        /// Module whose context files carried the **primary declaration**, when
        /// that was not the target. Drives the foreign-type import and the
        /// foreign-access skip rule.
        var declaringModule: String?
        /// Access level of the primary declaration. `.implicit` until a
        /// primary decl is seen — an extension never restates it.
        var accessLevel: AccessLevel = .implicit
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
        /// Enum cases from the primary decl, for the Tier 4 `enumCases`
        /// strategy. Empty unless a primary enum decl contributed them.
        var enumCases: [EnumCase] = []
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
    struct RecordingContext {
        let filePath: String
        let converter: SourceLocationConverter
        /// `true` for a dependency's sources — recorded for knowledge, never
        /// for emission. See `scan(sourceFiles:contextFiles:)`.
        let isContext: Bool
        /// Module a context file belongs to, when the caller attributed one
        /// (`--context-files SwiftSyntax=/path/File.swift`). `nil` for target
        /// files and for unattributed context.
        let moduleName: String?
    }

    private static func makeEntries(
        from perType: [String: TypeAggregate],
        shapes shapesByName: [String: TypeShape],
        aliases: [String: String],
        sendableProtocols: Set<String>
    ) -> [ConformanceMap.Entry] {
        // The whole-module type universe (built once in `scan`) lets nested
        // custom-type members/parameters resolve (Tier 3). Every scanned type
        // is included — even non-conformance-bearing helper types — so a
        // referenced type still resolves when it isn't itself a test target.
        let resolver = GeneratorResolver(types: Array(shapesByName.values), aliases: aliases)
        // Skipped types stay in `shapesByName` above — a `private` helper
        // struct is still a fine *member* type for a public type's generator,
        // and dropping it from the resolver universe would cost derivations
        // that compile perfectly well. Only the emitted suite goes away.
        let usable = perType.keys.sorted().filter {
            perType[$0]!.seenInTarget
                && skipReason(for: perType[$0]!, sendableProtocols: sendableProtocols) == nil
        }
        return usable.map { typeName -> ConformanceMap.Entry in
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
                ),
                declaringModule: aggregate.declaringModule
            )
        }
    }

    /// True when `memberBlock` declares a `static func gen()` method.
    /// The plugin sees the whole module so this catches gen() defined in
    /// the primary body OR in any extension.
    static func hasGenMethod(in memberBlock: MemberBlockSyntax) -> Bool {
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
    struct RecordRequest {
        let name: String
        let accessLevel: AccessLevel
        let inheritance: InheritanceClauseSyntax?
        let node: Syntax
        let kind: ConformanceMap.ProvenanceKind
        let typeKind: TypeShape.Kind?
        let hasUserGen: Bool
        let storedMembers: [StoredMember]
        let hasUserInit: Bool
        let initializers: [InitializerSignature]
        let enumCases: [EnumCase]
        let witnesses: WitnessSet
        let memberFunctions: [FunctionSignature]
    }

    static func record(
        _ request: RecordRequest,
        context: RecordingContext,
        into perType: inout [String: TypeAggregate]
    ) {
        var aggregate = perType[request.name] ?? TypeAggregate()
        // Latches: one target file mentioning the type is enough to make it
        // this target's to test, however many context files also describe it.
        if !context.isContext { aggregate.seenInTarget = true }
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
            aggregate.accessLevel = request.accessLevel
            // Only a context declaration attributes a module; a target
            // declaration clears it, so a name declared on both sides is
            // treated as the target's (matching the walk order).
            aggregate.declaringModule = context.isContext ? context.moduleName : nil
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
        if !request.enumCases.isEmpty {
            aggregate.enumCases = request.enumCases
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
