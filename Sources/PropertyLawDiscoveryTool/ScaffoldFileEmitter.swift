import PropertyLawCore

/// Assembles the opt-in scaffold file: a `gen()` stub for each `.todo` type
/// that has a known constructor (own struct/enum), with derivable slots filled
/// and the rest left as `<#…#>` placeholders. Separate from the auto-test file
/// (`GeneratedFileEmitter`) precisely because placeholders don't compile — the
/// developer reviews, completes, and moves these into a test target.
enum ScaffoldFileEmitter {

    /// The scaffold file text, or `nil` when nothing is scaffoldable (every
    /// type either fully derives or has no constructor to lift through).
    static func emit(map: ConformanceMap) -> String? {
        let resolver = GeneratorResolver(types: Array(map.shapesByName.values))
        var stubs: [String] = []
        // `entries` is already sorted by type name → deterministic output.
        for entry in map.entries {
            guard case .todo = entry.derivationStrategy,
                  let shape = map.shapesByName[entry.typeName],
                  let stub = ScaffoldEmitter.stub(for: shape, resolve: resolver.customTypeGenerator)
            else { continue }
            stubs.append(stub)
        }
        guard !stubs.isEmpty else { return nil }

        var lines: [String] = []
        lines.append("// SCAFFOLDED GENERATORS — review, complete each <#...#> placeholder,")
        lines.append("// then move these into your test target (the types must be in scope).")
        lines.append("//")
        lines.append("// \(stubs.count) type(s) partially derived — the rest needs your domain knowledge.")
        lines.append("")
        lines.append("import PropertyLawKit")
        lines.append("import Foundation")
        lines.append("")
        lines.append(stubs.joined(separator: "\n\n"))
        return lines.joined(separator: "\n") + "\n"
    }
}
