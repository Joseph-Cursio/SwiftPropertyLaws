import PropertyBased
import Testing
@testable import PropertyLawKit

/// Walking action sequences — and measuring what it actually buys over
/// sampling them, which turned out not to be what the design note assumed.
private enum Move: CaseIterable, Sendable {
    case deposit, withdraw, freeze, unfreeze
}

private struct Account: Equatable, Sendable {
    var balance = 0
    var frozen = false
}

private struct BalanceNeverNegative: InteractionInvariant, Sendable {
    typealias State = Account
    static func invariantHolds(in state: Account) -> Bool { state.balance >= 0 }
}

@Suite("Walked action sequences")
struct WalkedActionSequenceTests {

    /// The plant: `withdraw` checks the balance, except while frozen. So the
    /// shortest path to a negative balance is `freeze` then `withdraw`.
    private static let buggyReducer: @Sendable (Account, Move) -> Account = { state, move in
        var next = state
        switch move {
        case .deposit: next.balance += 1
        case .withdraw:
            if next.frozen { next.balance -= 1 }        // the bug: no balance check
            else if next.balance > 0 { next.balance -= 1 }
        case .freeze: next.frozen = true
        case .unfreeze: next.frozen = false
        }
        return next
    }

    private func violates(_ moves: [Move]) -> Bool {
        var state = Account()
        for move in moves {
            state = Self.buggyReducer(state, move)
            if !BalanceNeverNegative.invariantHolds(in: state) { return true }
        }
        return false
    }

    // MARK: - The harness

    @Test("the walked entry catches the invariant violation")
    func theWalkedEntryCatchesTheViolation() async {
        var reported: CheckResult?
        do {
            _ = try await checkInteractionInvariantPropertyLaws(
                for: BalanceNeverNegative.self,
                initialState: Account(),
                reducer: Self.buggyReducer,
                overEverySequenceUpTo: 4
            )
        } catch let violation as PropertyLawViolation {
            reported = violation.results.first
        } catch {}
        #expect(reported?.isViolation == true)
        // 4 moves, lengths 0...4: 1 + 4 + 16 + 64 + 256 = 341 sequences.
        #expect(reported?.coverage?.spaceSize == 341)
    }

    @Test("a correct reducer clears every sequence in the space")
    func aCorrectReducerClearsTheWholeSpace() async throws {
        let fixed: @Sendable (Account, Move) -> Account = { state, move in
            var next = state
            switch move {
            case .deposit: next.balance += 1
            case .withdraw: if next.balance > 0 { next.balance -= 1 }
            case .freeze: next.frozen = true
            case .unfreeze: next.frozen = false
            }
            return next
        }
        let results = try await checkInteractionInvariantPropertyLaws(
            for: BalanceNeverNegative.self,
            initialState: Account(),
            reducer: fixed,
            overEverySequenceUpTo: 4
        )
        #expect(results.allSatisfy { !$0.isViolation })
        #expect(results.first?.coverage?.isComplete == true)
    }

    // MARK: - The measurement

    /// **What walking buys here is minimality, not detection.**
    ///
    /// The violation is easy to reach: any sequence containing `freeze` before a
    /// `withdraw` at zero balance hits it, so sampling finds it essentially
    /// always. What sampling reports is a whole draw — the default length is
    /// `0...16` — while the walk reports the two moves that prove it.
    @Test("sampling finds it too, and reports a far longer witness")
    func samplingFindsItButReportsAMuchLongerWitness() {
        let space = Every.sequences(
            "actions",
            of: Every.elements("action", in: Move.allCases),
            upTo: 4
        )
        let walked = space.indices.first { violates(space[$0]) }.map { space[$0] }
        #expect(walked == [.freeze, .withdraw], "the walk should report the shortest path")

        let generator = ActionSequenceFactory.actionSequence(forCaseIterable: Move.self)
        var lengths: [Int] = []
        var missed = 0
        for seed in UInt64(0) ..< 50 {
            var rng = Xoshiro(seed: (seed &+ 1, 2, 3, 4))
            var found: [Move]?
            for _ in 0 ..< 200 where found == nil {
                let candidate = generator.run(using: &rng)
                if violates(candidate) { found = candidate }
            }
            if let found { lengths.append(found.count) } else { missed += 1 }
        }

        #expect(missed == 0, "sampling detects this reliably — detection is not the gap")
        let median = lengths.sorted()[lengths.count / 2]
        #expect(median > 2, "if sampling already reported minimal witnesses the walk buys nothing here")
    }

    /// The honest counterweight: the space grows as `|A|^k`, so this only works
    /// for short prefixes. Four moves to length eight is already 87 381
    /// sequences and to length twelve it is 22 369 621.
    @Test("the sequence space is exponential, which bounds where this applies")
    func theSpaceGrowsExponentially() {
        let alphabet = Every.elements("action", in: Move.allCases)
        #expect(Every.sequences("a", of: alphabet, upTo: 4).count == 341)
        #expect(Every.sequences("a", of: alphabet, upTo: 8).count == 87_381)
        #expect(Every.sequences("a", of: alphabet, upTo: 12).count == 22_369_621)
    }
}
