import Testing
import PropertyBased
@testable import PropertyLawKit

struct IteratorPropertyLawsTests {

    @Test func arrayIteratorPassesAllLaws() async throws {
        let results = try await checkIteratorProtocolPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            options: LawCheckOptions(budget: .standard)
        )
        #expect(results.allSatisfy { $0.outcome == .passed })
        let names = results.map(\.protocolLaw)
        #expect(names.contains("IteratorProtocol.terminationStability"))
        #expect(names.contains("IteratorProtocol.singlePassYield"))
    }

    @Test func detectsResumingAfterNil() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkIteratorProtocolPropertyLaws(
                for: ResumingAfterNilSequence.self,
                using: Gen<ResumingAfterNilSequence>.resumingAfterNil(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("IteratorProtocol.terminationStability"),
            "expected terminationStability in violation set; got: \(laws)"
        )
    }

    @Test func detectsInfiniteIterator() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkIteratorProtocolPropertyLaws(
                for: InfiniteCounterSequence.self,
                using: Gen<InfiniteCounterSequence>.infiniteCounter(),
                options: LawCheckOptions(budget: .sanity, enforcement: .strict)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(
            laws.contains("IteratorProtocol.singlePassYield"),
            "expected singlePassYield in violation set; got: \(laws)"
        )
    }

    @Test func conventionalLawsDoNotThrowByDefault() async throws {
        // Both laws are Conventional; default enforcement reports violations as `.failed` results
        // but does not throw.
        //
        // The `withKnownIssue` is the point. "Reports" now means something: the violation surfaces
        // as a non-fatal Testing issue as well as a `.failed` result. Before that, this test passed
        // on *silence* — the kit knew the law was broken and said nothing, and nothing here would
        // have noticed if the `.failed` result had gone missing too.
        await withKnownIssue("a Conventional violation is visible, by design — it just does not throw") {
            let results = try await checkIteratorProtocolPropertyLaws(
                for: ResumingAfterNilSequence.self,
                using: Gen<ResumingAfterNilSequence>.resumingAfterNil(),
                options: LawCheckOptions(budget: .sanity)
            )
            #expect(results.contains { $0.isViolation && $0.tier == .conventional })
        }
    }
}
