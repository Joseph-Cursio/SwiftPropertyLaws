import Foundation
import Testing
import PropertyBased
@testable import PropertyLawKit

struct TransformationFunctionLawsTests {

    /// Element-moving functions per the family's guidance: both maps
    /// change values, the predicate splits the generated domain.
    private static let intFunctions = TransformationFunctions<Int>(
        first: { $0 &* 2 },
        second: { $0 &+ 7 },
        predicate: { $0 % 3 == 0 }
    )

    @Test func arrayOfIntPassesAllParameterizedLaws() async throws {
        let results = try await checkTransformationPropertyLaws(
            for: [Int].self,
            using: TestGen.smallInt().array(of: 0...8),
            functions: Self.intFunctions,
            options: LawCheckOptions(budget: .standard)
        )
        let names = results.map(\.protocolLaw)
        #expect(names.contains("Transformation.mapFusion"))
        #expect(names.contains("Transformation.mapFilterCommutation"))
        #expect(names.contains("Transformation.lazyMapEquivalence"))
        #expect(names.contains("Transformation.lazyFilterEquivalence"))
        #expect(results.allSatisfy { $0.outcome == .passed })
    }

    /// Negative control from the family header: a stateful map breaks
    /// fusion (the two-pass pipeline calls it in a different order than
    /// the fused one). Uses an impure closure deliberately.
    @Test func statefulFunctionSurfacesFusionViolation() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next() -> Int {
                lock.lock()
                defer { lock.unlock() }
                value += 1
                return value
            }
        }
        let counter = Counter()
        let impure = TransformationFunctions<Int>(
            first: { $0 &+ counter.next() },
            second: { $0 },
            predicate: { _ in true }
        )
        let violation = await #expect(throws: PropertyLawViolation.self) {
            try await checkTransformationPropertyLaws(
                for: [Int].self,
                using: TestGen.smallInt().array(of: 2...8),
                functions: impure,
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let laws = violation?.results.map(\.protocolLaw) ?? []
        #expect(laws.isEmpty == false, "expected the impure map to violate at least one law")
    }
}
