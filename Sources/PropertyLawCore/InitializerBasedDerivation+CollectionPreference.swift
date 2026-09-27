/// The two helpers `initializerBasedStrategy` uses to derive one initializer and to prefer a
/// collection form over a single-element one. Split from `InitializerBasedDerivation.swift` for length.
extension DerivationStrategist {

    /// Each parameter's generator, or `nil` when any parameter has none.
    static func derivedArguments(
        _ initializer: InitializerSignature,
        resolve: CustomTypeResolver
    ) -> [InitArgument]? {
        var arguments: [InitArgument] = []
        for parameter in initializer.parameters {
            guard let resolved = composedGenerator(forTypeName: parameter.typeName, resolve: resolve) else {
                return nil
            }
            let composed = narrowedByLabel(resolved, label: parameter.label, typeName: parameter.typeName)
            arguments.append(InitArgument(
                label: parameter.label,
                generatorExpression: composed.expression,
                requiredImports: composed.requiredImports
            ))
        }
        return arguments
    }

    /// A later one-parameter initializer taking `[T]` where `initializer` takes one `T`, or `nil`.
    ///
    /// **One element is a corner of the domain, and a type that offers both says so.** BigInt's
    /// `BigUInt` declares `init(word: Word)` before `init(words: [Word])`, and first-in-order drew
    /// every value from a single machine word — so a multiplication returned through its `count == 1`
    /// fast path on every trial and its long-multiplication loop was reached by no draw at all
    /// (`mutation-check-arithmetic.md` in SwiftInferProperties). The collection form draws zero to
    /// several elements, which includes the single-element values. Deliberately this narrow: only
    /// the exact `T` / `[T]` pair on one parameter each, so no other type's choice moves.
    static func collectionAlternative(
        to initializer: InitializerSignature,
        among later: ArraySlice<InitializerSignature>
    ) -> InitializerSignature? {
        guard initializer.parameters.count == 1, let element = initializer.parameters.first?.typeName else {
            return nil
        }
        let spellings: Set<String> = ["[\(element)]", "Array<\(element)>"]
        return later.first { candidate in
            candidate.parameters.count == 1
                && spellings.contains(String(candidate.parameters[0].typeName.filter { $0 != " " }))
        }
    }
}
