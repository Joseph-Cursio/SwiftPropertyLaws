// `@unchecked Sendable`: `PartialKeyPath` is an immutable reference type in
// practice but isn't declared `Sendable` by the standard library. KeyPaths
// passed into `.partial(fields:)` are read-only views into property storage;
// we never mutate them and the array is consumed by reading inside a single
// trial. Safe enough for the Sendable contract under Swift 6 strict
// concurrency until the standard library annotates `PartialKeyPath` itself.

/// How `checkCodablePropertyLaws` compares a value to its round-tripped form
/// (PRD §4.3 Codable table).
///
/// - `.strict` — exact `==` equality.
/// - `.semantic(equivalent:)` — caller-supplied equivalence predicate, for
///   schemas with intentionally lossy representational round-trip
///   (canonicalised dates, normalised whitespace, …).
/// - `.partial(fields:)` — round-trip preserves a named subset of fields, for
///   versioned schemas with default-bearing additions. Field equality is
///   compared via `String(describing:)` of each value at each `PartialKeyPath`,
///   which is type-safe (key paths can't drift on rename) and works for any
///   field whose `String(describing:)` is stable. Values whose `String(describing:)`
///   is non-deterministic (Sets, Dictionaries with non-stable order) should
///   use `.semantic(equivalent:)` instead.
public enum CodableRoundTripMode<T: Sendable>: @unchecked Sendable {
    case strict
    case semantic(equivalent: @Sendable (T, T) -> Bool)
    case partial(fields: [PartialKeyPath<T>])

    /// `.semantic` and `.partial` can pass with field-level diffs; `.strict`
    /// can't (any diff is the violation), so near-miss tracking is moot
    /// there.
    var tracksFieldLevelNearMisses: Bool {
        switch self {
        case .strict: return false
        case .semantic, .partial: return true
        }
    }
}
