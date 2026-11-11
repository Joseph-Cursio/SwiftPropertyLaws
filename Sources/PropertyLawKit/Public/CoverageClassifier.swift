/// Type-erased wrapper for a `CoverageClassifier`. The kit's per-suite
/// `coverage:` parameter is `AnyCoverageClassifier<Value>?` rather than a
/// raw existential because Swift's existential `any CoverageClassifier`
/// can't bind the `Input` associated type at the call site.
public struct AnyCoverageClassifier<Input: Sendable>: Sendable {
    private let classifyImpl: @Sendable (Input) -> (classes: Set<String>, boundaries: Set<String>)

    public init<Wrapped: CoverageClassifier>(
        _ wrapped: Wrapped
    ) where Wrapped.Input == Input {
        self.classifyImpl = { wrapped.classify($0) }
    }

    /// Build directly from a closure when you don't want a named conformance.
    public init(
        classify: @Sendable @escaping (Input) -> (classes: Set<String>, boundaries: Set<String>)
    ) {
        self.classifyImpl = classify
    }

    public func classify(_ input: Input) -> (classes: Set<String>, boundaries: Set<String>) {
        classifyImpl(input)
    }
}

// MARK: - Stdlib defaults

/// Classifier for `Int` samples — sign categories + Int.min / Int.max
/// boundary hits. Expected use: `coverage: AnyCoverageClassifier(IntCoverage())`
/// on `checkEquatablePropertyLaws(for: Int.self, ...)` etc.
public struct IntCoverage: CoverageClassifier {
    public init() {
        // Stateless: nothing to configure.
    }

    public func classify(_ input: Int) -> (classes: Set<String>, boundaries: Set<String>) {
        var classes: Set<String> = []
        if input == 0 { classes.insert("zero") }
        if input < 0 { classes.insert("negative") }
        if input > 0 { classes.insert("positive") }

        var boundaries: Set<String> = []
        if input == Int.min { boundaries.insert("Int.min") }
        if input == Int.max { boundaries.insert("Int.max") }
        return (classes, boundaries)
    }
}

/// Classifier for `Bool` samples — straightforward true/false bucketing.
public struct BoolCoverage: CoverageClassifier {
    public init() {
        // Stateless: nothing to configure.
    }

    public func classify(_ input: Bool) -> (classes: Set<String>, boundaries: Set<String>) {
        ([input ? "true" : "false"], [])
    }
}

/// Classifier for `String` samples — emptiness / ASCII vs Unicode classes,
/// single-character boundary.
public struct StringCoverage: CoverageClassifier {
    public init() {
        // Stateless: nothing to configure.
    }

    public func classify(_ input: String) -> (classes: Set<String>, boundaries: Set<String>) {
        var classes: Set<String> = []
        if input.isEmpty {
            classes.insert("empty")
        } else if input.allSatisfy(\.isASCII) {
            classes.insert("ascii")
        } else {
            classes.insert("unicode")
        }

        var boundaries: Set<String> = []
        if input.count == 1 { boundaries.insert("single-character") }
        return (classes, boundaries)
    }
}

/// Classifier for `Array<Element>` samples — empty / single-element /
/// multi-element classes.
public struct ArrayCoverage<Element: Sendable>: CoverageClassifier {
    public init() {
        // Stateless: nothing to configure.
    }

    public func classify(_ input: [Element]) -> (classes: Set<String>, boundaries: Set<String>) {
        var classes: Set<String> = []
        switch input.count {
        case 0: classes.insert("empty")
        case 1: classes.insert("single-element")
        default: classes.insert("multi-element")
        }
        return (classes, [])
    }
}

/// Classifies sampled inputs into named buckets so per-trial distribution
/// shows up on `CheckResult.coverageHints` (PRD §4.6).
///
/// Two bucket sets per classification:
/// - `classes`: orthogonal categories the input falls into. Counted
///   independently — an input may fall into more than one class. Surfaces
///   the "all my Int samples were tiny" failure mode.
/// - `boundaries`: named boundary values the input hit (`Int.min`,
///   `empty-string`, `single-character`). Surfaces "I never tested the
///   actual edge case I claimed to cover."
public protocol CoverageClassifier<Input>: Sendable {
    associatedtype Input: Sendable
    func classify(_ input: Input) -> (classes: Set<String>, boundaries: Set<String>)
}
