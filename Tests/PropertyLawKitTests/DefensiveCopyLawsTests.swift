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

    /// Every non-empty script reaches the shared box, so a script of four or
    /// more mutations must shrink to one. No other test read the script, so a
    /// shrinker that returned nothing passed.
    @Test func shallowCopyShrinksToASingleMutation() async throws {
        let violation = await #expect(throws: PropertyLawViolation.self) {
            _ = try await checkDefensiveCopyPropertyLaws(
                for: ShallowCopy.self,
                length: 4...8,
                options: LawCheckOptions(budget: .sanity)
            )
        }
        let shallow = violation?.results.first { $0.protocolLaw == "DefensiveCopy.copyIsIndependent" }
        guard case .failed(let counterexample) = shallow?.outcome else {
            Issue.record("expected copyIsIndependent to fail; got \(String(describing: shallow))")
            return
        }
        #expect(counterexample.contains("applying [bump] to the copy alone"), "\(counterexample)")
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
