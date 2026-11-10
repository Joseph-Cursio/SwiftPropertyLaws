import PropertyBased
@testable import PropertyLawKit
import Testing

struct SetAlgebraLawsTests {

    @Test func setOfIntPassesAllLaws() async throws {
        let results = try await checkSetAlgebraPropertyLaws(
            for: Set<Int>.self,
            using: setOfIntGen(),
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("SetAlgebra.unionIdempotence"))
        #expect(names.contains("SetAlgebra.intersectionIdempotence"))
        #expect(names.contains("SetAlgebra.unionCommutativity"))
        #expect(names.contains("SetAlgebra.intersectionCommutativity"))
        #expect(names.contains("SetAlgebra.emptyIdentity"))
        #expect(names.contains("SetAlgebra.symmetricDifferenceSelfIsEmpty"))
        #expect(names.contains("SetAlgebra.symmetricDifferenceEmptyIdentity"))
        #expect(names.contains("SetAlgebra.symmetricDifferenceCommutativity"))
        #expect(names.contains("SetAlgebra.symmetricDifferenceDefinition"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    @Test func eachLawIsStrictTier() async throws {
        let results = try await checkSetAlgebraPropertyLaws(
            for: Set<Int>.self,
            using: setOfIntGen(),
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.allSatisfy { $0.tier == .strict })
    }

    @Test func detectsLeftBiasedUnion() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: LeftBiasedUnion.self,
                using: Gen<LeftBiasedUnion>.leftBiasedUnion(),
                options: LawCheckOptions(budget: .standard)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.unionCommutativity"),
            "expected unionCommutativity; got: \(laws)"
        )
    }

    @Test func detectsEmptyingIntersection() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkSetAlgebraPropertyLaws(
                for: EmptyingIntersection.self,
                using: Gen<EmptyingIntersection>.emptyingIntersection(),
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("SetAlgebra.intersectionIdempotence"),
            "expected intersectionIdempotence; got: \(laws)"
        )
    }

    private func setOfIntGen() -> Generator<Set<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 0...6)
            .map(Set.init)
    }
}
