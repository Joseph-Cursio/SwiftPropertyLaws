import SwiftSyntax

/// How the scan keeps a dependency's type from merging into a target type that
/// happens to share its name.
///
/// Split from `ModuleScanner.swift` to keep that file under the 400-line lint,
/// following the `ModuleScanner+Shapes.swift` precedent.
extension ModuleScanner {

    /// Qualified names of the types the target itself declares.
    ///
    /// **A dependency's type of the same name is a different type**, and inside
    /// the target the target's own declaration is the one the name means: Swift
    /// looks in the current module before any import. The scan keys types by
    /// name alone, so it used to merge the two. Context is walked first, and
    /// the target's members won by arriving last, but conformances,
    /// provenances and witnesses accumulated from both. Measured 2026-10-29 by
    /// PRD §8 Pass 1 through the plugin: Sitrep declares a `Node`, its
    /// dependency Yams declares an unrelated `Node` that is `Hashable` and
    /// `Comparable`, and Sitrep's `Node` got checks for both conformances,
    /// which it does not have. A derivable generator would have made that a
    /// suite that does not compile, taking the test target with it.
    ///
    /// So context files are absorbed with these names hidden. The target files
    /// are walked once more for this, which is cheap: they are already parsed.
    static func typesDeclared(
        in targetFiles: [(file: ScannedFile, tree: SourceFileSyntax)]
    ) -> Set<String> {
        var declared: [String: TypeAggregate] = [:]
        var unusedAliases: [String: String] = [:]
        for (file, parsed) in targetFiles {
            absorb(parsed, from: file, hiding: [], into: &declared, aliases: &unusedAliases)
        }
        return Set(declared.filter { $0.value.typeKind != nil }.keys)
    }
}

extension ModuleScanner.RecordingContext {

    /// Whether `name`, or a type it is nested in, is hidden. Nested names
    /// count because `Node.Scalar` in a dependency belongs to the
    /// dependency's `Node`, not to the target's.
    func hides(_ name: String) -> Bool {
        guard !hidden.isEmpty else { return false }
        var prefix = ""
        for component in name.split(separator: ".") {
            prefix = prefix.isEmpty ? String(component) : prefix + "." + component
            if hidden.contains(prefix) { return true }
        }
        return false
    }
}
