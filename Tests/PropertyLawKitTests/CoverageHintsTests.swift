@testable import PropertyLawKit
import Testing

struct CoverageHintsTests {

    // MARK: - Stdlib classifiers — direct tests of classify()

    @Test func intCoverageClassifiesSign() {
        let classifier = IntCoverage()
        let zero = classifier.classify(0)
        #expect(zero.classes == ["zero"])
        let negative = classifier.classify(-5)
        #expect(negative.classes == ["negative"])
        let positive = classifier.classify(42)
        #expect(positive.classes == ["positive"])
    }

    @Test func intCoverageHitsBoundaries() {
        let classifier = IntCoverage()
        #expect(classifier.classify(Int.min).boundaries == ["Int.min"])
        #expect(classifier.classify(Int.max).boundaries == ["Int.max"])
        #expect(classifier.classify(7).boundaries.isEmpty)
    }

    @Test func boolCoverageBuckets() {
        let classifier = BoolCoverage()
        #expect(classifier.classify(true).classes == ["true"])
        #expect(classifier.classify(false).classes == ["false"])
    }

    @Test func stringCoverageBuckets() {
        let classifier = StringCoverage()
        #expect(classifier.classify("").classes == ["empty"])
        #expect(classifier.classify("hi").classes == ["ascii"])
        #expect(classifier.classify("héllo").classes == ["unicode"])
        #expect(classifier.classify("a").boundaries == ["single-character"])
    }

    @Test func arrayCoverageBuckets() {
        let classifier = ArrayCoverage<Int>()
        #expect(classifier.classify([]).classes == ["empty"])
        #expect(classifier.classify([1]).classes == ["single-element"])
        #expect(classifier.classify([1, 2, 3]).classes == ["multi-element"])
    }

    // MARK: - Coverage hints flow through Equatable.reflexivity

    @Test func reflexivityPopulatesCoverageWhenClassifierGiven() async throws {
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .standard),
            coverage: AnyCoverageClassifier(IntCoverage())
        )
        let reflexivity = try #require(
            results.first { $0.protocolLaw == "Equatable.reflexivity" }
        )
        let hints = try #require(reflexivity.coverageHints)
        // 1,000 trials over -100...100 should cover all three sign classes.
        let totalClassified = hints.inputClasses.values.reduce(0, +)
        #expect(totalClassified == 1_000)
        #expect(hints.inputClasses["zero"] != nil)
        #expect(hints.inputClasses["negative"] != nil)
        #expect(hints.inputClasses["positive"] != nil)
    }

    @Test func nilCoverageLeavesCheckResultCoverageHintsNil() async throws {
        // Without a classifier, coverageHints should stay nil — preserving
        // the §4.6 "this law doesn't track" semantic.
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
        let reflexivity = try #require(
            results.first { $0.protocolLaw == "Equatable.reflexivity" }
        )
        #expect(reflexivity.coverageHints == nil)
    }

    @Test func tupleInputLawsIgnoreClassifier() async throws {
        // Symmetry takes a pair, not a single Value. The kit doesn't apply
        // the unary-input classifier there — coverageHints stays nil.
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            coverage: AnyCoverageClassifier(IntCoverage())
        )
        let symmetry = try #require(
            results.first { $0.protocolLaw == "Equatable.symmetry" }
        )
        #expect(symmetry.coverageHints == nil)
    }

    // MARK: - Coverage hints flow through Hashable.distribution (aggregate)

    @Test func hashableDistributionPopulatesCoverage() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .standard),
            laws: .ownOnly,
            coverage: AnyCoverageClassifier(IntCoverage())
        )
        let distribution = try #require(
            results.first { $0.protocolLaw == "Hashable.distribution" }
        )
        let hints = try #require(distribution.coverageHints)
        let totalClassified = hints.inputClasses.values.reduce(0, +)
        #expect(totalClassified == 1_000)
    }

    @Test func hashableStabilityPopulatesCoverage() async throws {
        let results = try await checkHashablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity),
            laws: .ownOnly,
            coverage: AnyCoverageClassifier(IntCoverage())
        )
        let stability = try #require(
            results.first { $0.protocolLaw == "Hashable.stabilityWithinProcess" }
        )
        let hints = try #require(stability.coverageHints)
        let totalClassified = hints.inputClasses.values.reduce(0, +)
        #expect(totalClassified == 100)
    }

    // MARK: - Closure-init form for ad-hoc classifiers

    @Test func closureInitClassifierWorksWithoutNamedConformance() async throws {
        let custom = AnyCoverageClassifier<Int> { input in
            (classes: input.isMultiple(of: 2) ? ["even"] : ["odd"], boundaries: [])
        }
        let results = try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .standard),
            coverage: custom
        )
        let reflexivity = try #require(
            results.first { $0.protocolLaw == "Equatable.reflexivity" }
        )
        let hints = try #require(reflexivity.coverageHints)
        #expect(hints.inputClasses["even"] != nil)
        #expect(hints.inputClasses["odd"] != nil)
    }
}
