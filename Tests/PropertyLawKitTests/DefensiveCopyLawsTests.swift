import Testing
import PropertyBased
@testable import PropertyLawKit

/// v3.7.0 — tests for `checkDefensiveCopyPropertyLaws`. Three hand-rolled class
/// conformers: a correct deep copy (positive control), a `return self` copy
/// (fails distinctness), and a shallow copy sharing a mutable reference (fails
/// independence). Fixtures mirror pbt-book Chapter 9 §9.3.
struct DefensiveCopyLawsTests {

    @Test func correctDeepCopyPassesBothLaws() async throws {
        let results = try await checkDefensiveCopyPropertyLaws(
            for: CorrectCopy.self,
            options: LawCheckOptions(budget: .sanity)
        )
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.isViolation == false })
        #expect(results.allSatisfy { $0.tier == .strict })
        #expect(results.map(\.protocolLaw) == [
            "DefensiveCopy.copyIsDistinctInstance",
            "DefensiveCopy.copyIsIndependent"
        ])
    }

    @Test func returnSelfCopyIsDetected() async throws {
        // `copyUnderTest()` returns `self` → fails copyIsDistinctInstance.
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkDefensiveCopyPropertyLaws(
                for: ReturnSelfCopy.self,
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }

    @Test func shallowCopyIsDetected() async throws {
        // A distinct instance that shares a mutable reference → passes
        // distinctness but fails copyIsIndependent.
        await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkDefensiveCopyPropertyLaws(
                for: ShallowCopy.self,
                options: LawCheckOptions(budget: .sanity)
            )
        }
    }
}

// MARK: - Fixtures: correct deep copy (positive control)

final class CorrectCopy: DefensiveCopy, @unchecked Sendable {
    private var items: [Int] = []

    static func == (lhs: CorrectCopy, rhs: CorrectCopy) -> Bool { lhs.items == rhs.items }
    static func makeProbe() -> CorrectCopy { CorrectCopy() }

    func copyUnderTest() -> CorrectCopy {
        let copy = CorrectCopy()
        copy.items = items   // value array → deep-copied by assignment
        return copy
    }

    enum Mutation: CaseIterable, Sendable { case append }

    static func apply(_ mutation: Mutation, to target: CorrectCopy) {
        switch mutation {
        case .append: target.items.append(1)
        }
    }
}

// MARK: - Fixtures: `return self` (fails distinctness)

final class ReturnSelfCopy: DefensiveCopy, @unchecked Sendable {
    private var items: [Int] = []

    static func == (lhs: ReturnSelfCopy, rhs: ReturnSelfCopy) -> Bool { lhs.items == rhs.items }
    static func makeProbe() -> ReturnSelfCopy { ReturnSelfCopy() }

    // BUG: returns the same instance.
    func copyUnderTest() -> ReturnSelfCopy { self }

    enum Mutation: CaseIterable, Sendable { case append }

    static func apply(_ mutation: Mutation, to target: ReturnSelfCopy) {
        switch mutation {
        case .append: target.items.append(1)
        }
    }
}

// MARK: - Fixtures: shallow copy sharing a reference (fails independence)

final class ShallowCopy: DefensiveCopy, @unchecked Sendable {

    final class Box: @unchecked Sendable { var value: Int = 0 }
    private var box: Box = Box()

    static func == (lhs: ShallowCopy, rhs: ShallowCopy) -> Bool { lhs.box.value == rhs.box.value }
    static func makeProbe() -> ShallowCopy { ShallowCopy() }

    // Distinct instance, but shares the `box` reference — a shallow copy.
    func copyUnderTest() -> ShallowCopy {
        let copy = ShallowCopy()
        copy.box = box
        return copy
    }

    enum Mutation: CaseIterable, Sendable { case bump }

    static func apply(_ mutation: Mutation, to target: ShallowCopy) {
        switch mutation {
        case .bump: target.box.value += 1
        }
    }
}
