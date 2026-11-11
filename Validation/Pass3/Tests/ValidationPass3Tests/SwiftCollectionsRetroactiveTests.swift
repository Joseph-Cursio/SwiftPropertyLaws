import Testing
import HashTreeCollections
import PropertyLawKit

/// Pass 3 validation (PRD §8): retroactive investigation of a real
/// `swift-collections` commit, plus the empirical finding that closed it.
///
/// **What we set out to do.** Commit `swift-collections@35349601` ("Typo:
/// symmetric difference should be the xor, not intersection") fixed a
/// one-character bug in `_Bitmap.symmetricDifference` — `&` (intersection)
/// was changed to `^` (xor):
///
/// ```swift
/// // Pre-fix:
/// internal func symmetricDifference(_ other: Self) -> Self {
///     Self(_value: _value & other._value)   // & = intersection
/// }
/// // Post-fix:
/// internal func symmetricDifference(_ other: Self) -> Self {
///     Self(_value: _value ^ other._value)   // ^ = xor (correct)
/// }
/// ```
///
/// The plan: pin `swift-collections` to the buggy parent SHA `8e5e4a8f`
/// and demonstrate that `checkSetAlgebraPropertyLaws(TreeSet<Int>.self, ...)`
/// retroactively catches the violation through the four `symmetricDifference*`
/// laws added to PRD §4.3 SetAlgebra in response to this finding.
///
/// **What we actually found.** At the buggy SHA, `TreeSet.symmetricDifference`
/// returns the *correct* answer for every input — including Apple's own
/// regression test inputs. Tracing through the source: `_Bitmap.symmetricDifference`
/// is defined but **never called** from the public path. `TreeSet.symmetricDifference`
/// dispatches to `_HashNode.symmetricDifference` → `_HashNode._symmetricDifference`
/// → `_HashNode._symmetricDifference_slow*`, which builds the result
/// element-by-element via the structural traversal in
/// `_HashNode+Structural symmetricDifference.swift`. None of those call
/// `_Bitmap.symmetricDifference`. The buggy method is dead code at the
/// pinned SHA — Apple's "regression test" guards against future code that
/// might begin using `_Bitmap.symmetricDifference`, not against an
/// observable user-facing bug.
///
/// This test target therefore asserts the *empirical truth*: `TreeSet`
/// passes every kit law at the buggy SHA, including all four
/// `symmetricDifference*` laws — because no public API exercises the
/// buggy code. The kit's checks are *not* false-positive: they faithfully
/// reflect the public semantics, even when the source contains visible
/// (but unreachable) bugs.
///
/// **Implication for PRD §8.** The §8 1.0 gate ("catch a real semantic
/// conformance bug in 5+ popular packages before 1.0") is empirically
/// hard to close against well-maintained packages. The git-archaeology
/// pass that surfaced commit `35349601` searched four full-history
/// repos (~5,200 commits across `swift-argument-parser`,
/// `swift-aws-lambda-runtime`, `swift-collections`, `swift-nio`,
/// `hummingbird`); the only candidate that survived rejection was this
/// dead-code typo. See `Validation/FINDINGS.md` Pass 3 for the
/// rationale and the proposed §8 rewrite.
struct SwiftCollectionsRetroactiveTests {

    // MARK: - The empirical finding

    /// At the buggy parent SHA `8e5e4a8f`, `TreeSet<Int>` passes every
    /// kit-checked SetAlgebra law including the four `symmetricDifference*`
    /// laws. The buggy `_Bitmap.symmetricDifference` is dead code; the
    /// public `TreeSet.symmetricDifference` goes through structural
    /// traversal and is correct. The kit's no-violation result here is
    /// the *honest* answer.
    @Test func treeSetPassesAllLawsAtBuggySHA() async throws {
        try await checkSetAlgebraPropertyLaws(
            for: TreeSet<Int>.self,
            using: Gen<TreeSet<Int>>.treeSetOfInt(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    /// Re-runs Apple's own regression test for commit `35349601` against
    /// the pinned buggy SHA. Apple's test asserts
    /// `[1,3].symmetricDifference([2,3]) == [1,2]`. This test confirms that
    /// — at the buggy SHA — the assertion already holds, demonstrating the
    /// bug never surfaced through `TreeSet`'s public API.
    @Test func applesRegressionTestPassesAtBuggySHA() {
        let left: TreeSet<Int> = [1, 3]
        let right: TreeSet<Int> = [2, 3]
        let result = left.symmetricDifference(right)
        let actual = Set(result)
        // The buggy `_Bitmap.symmetricDifference` returned `& other._value`
        // (intersection), which would have yielded `{3}`. The fact that we
        // observe `{1, 2}` here proves the public path doesn't go through
        // `_Bitmap.symmetricDifference`. It's dead code at this SHA.
        #expect(
            actual == Set([1, 2]),
            "TreeSet.symmetricDifference is correct at the buggy SHA — confirming the dead-code finding."
        )
    }
}

// MARK: - Generator

extension Gen where Value == TreeSet<Int> {
    /// Generates `TreeSet<Int>` instances over a small element range. Range
    /// `0...20` and size `1...4` produce frequent partial overlap between
    /// two sampled sets — useful even when no violation is expected, as a
    /// stress test that the kit doesn't false-positive on real public
    /// implementations.
    static func treeSetOfInt() -> Generator<TreeSet<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: 0...20)
            .array(of: 1...4)
            .map { TreeSet($0) }
    }
}
