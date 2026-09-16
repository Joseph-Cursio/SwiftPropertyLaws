/// Why `GeneratorResolver` produced no generator for a type name.
///
/// `customTypeGenerator(forTypeName:)` answers `nil` from five places, and the
/// `nil` is all a caller used to get. The `.todo` path was the costly one: the
/// strategist had already written a sentence saying what blocked the type, and
/// `derive` threw it away. SwiftInferProperties' missing-generator census
/// (issue #48) then had to reconstruct two of the remaining paths and guess the
/// third, leaving **370 of 2 016 unresolved types (18.4%) unexplained** for no
/// reason other than that the answer had been discarded.
///
/// Ask with `GeneratorResolver.resolutionFailure(forTypeName:)`.
public enum ResolutionFailure: Sendable, Equatable {
    /// No type of this name was in the universe the resolver was built over —
    /// an external or stdlib type the scan did not include.
    case notInUniverse

    /// Two or more distinct types carry this name (bare or as a nested leaf),
    /// and the resolver refuses to guess between them. A qualified spelling
    /// resolves it. See `GeneratorResolver.init(types:aliases:)`.
    case ambiguous

    /// A typealias whose underlying spelling did not resolve.
    case aliasUnresolved(underlying: String)

    /// The type is in the universe and no derivation strategy applied. `reason`
    /// is the strategist's own `.todo` diagnostic, verbatim.
    case noStrategy(reason: String)

    /// The type refers back to itself with nothing to terminate the recursion —
    /// a bare `indirect enum` payload rather than an optional or collection.
    case unterminatedRecursion
}
