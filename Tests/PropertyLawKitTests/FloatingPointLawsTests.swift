import Testing
import PropertyBased
@testable import PropertyLawKit

struct FloatingPointLawsTests {

    @Test func doublesPassAlwaysOnLawsByDefault() async throws {
        let results = try await checkFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Double")
        }
        // 11 always-on laws (9 + additive/multiplicative commutativity);
        // allowNaN is false by default.
        #expect(results.count == 11)
    }

    @Test func floatsPassAlwaysOnLawsByDefault() async throws {
        let results = try await checkFloatingPointPropertyLaws(
            for: Float.self,
            using: Gen<Float>.float(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Float")
        }
    }

    @Test func allowNaNAddsNaNDomainLaws() async throws {
        let results = try await checkFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity, allowNaN: true)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass for Double")
        }
        // 11 always-on + 5 NaN-domain laws.
        #expect(results.count == 16)
        let names = results.map(\.protocolLaw)
        #expect(names.contains("FloatingPoint.nanIsNaN"))
        #expect(names.contains("FloatingPoint.nanInequality"))
    }

    @Test func nanProducingGeneratorPassesAlwaysOnLawsViaSkipGuards() async throws {
        // Use the NaN-injecting generator with allowNaN: false. The
        // always-on laws should still pass because they internally skip
        // non-finite samples for arithmetic-comparison checks.
        let results = try await checkFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.doubleWithNaN(),
            options: LawCheckOptions(budget: .standard)
        )
        for result in results {
            #expect(result.isViolation == false, "\(result.protocolLaw) should pass with NaN skip-guards")
        }
    }

    @Test func tiersAreReportedAsStrict() async throws {
        let results = try await checkFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity, allowNaN: true)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func lawNamesMatchPRD() async throws {
        let results = try await checkFloatingPointPropertyLaws(
            for: Double.self,
            using: Gen<Double>.double(in: -1_000.0...1_000.0),
            options: LawCheckOptions(budget: .sanity, allowNaN: true)
        )
        let names = Set(results.map(\.protocolLaw))
        #expect(names == [
            "FloatingPoint.infinityIsInfinite",
            "FloatingPoint.negativeInfinityComparison",
            "FloatingPoint.zeroIsZero",
            "FloatingPoint.signedZeroEquality",
            "FloatingPoint.roundedZeroIdentity",
            "FloatingPoint.additiveInverseFinite",
            "FloatingPoint.nextUpDownRoundTrip",
            "FloatingPoint.signMatchesIsLessThanZero",
            "FloatingPoint.absoluteValueNonNegative",
            "FloatingPoint.additionCommutativity",
            "FloatingPoint.multiplicationCommutativity",
            "FloatingPoint.nanIsNaN",
            "FloatingPoint.nanInequality",
            "FloatingPoint.nanPropagatesAddition",
            "FloatingPoint.nanPropagatesMultiplication",
            "FloatingPoint.nanComparisonIsUnordered"
        ])
    }
}
