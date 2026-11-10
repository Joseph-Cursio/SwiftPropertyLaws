import PropertyBased

/// v2.2.0 — namespace housing the `actionSequence` factories that
/// SwiftInferProperties v2.0 M2 consumes for its interaction-invariant
/// verify pipeline.
///
/// **Why a separate namespace rather than `extension DerivationStrategist`.**
/// The SwiftInferProperties v2.0 PRD §8.1 originally sketched these
/// entries as a `DerivationStrategist` extension, but `DerivationStrategist`
/// lives in `PropertyLawCore` (the plan-only layer — produces
/// `DerivationStrategy` enum values, no runtime `Generator`) and the
/// PRD wording predated a closer look at the kit's actual architecture.
/// `Generator<...>` lives one layer up in `PropertyLawKit` (which
/// `@_exported import`s `swift-property-based`), so the runtime-Gen-
/// producing factory needs to live here. Keeps the
/// `PropertyLawCore` plan-vs-runtime layering intact.
///
/// **Two entries:**
///   - `actionSequence(from:length:statefulGuards:)` — primary,
///     carrier-agnostic. Caller supplies any `Generator<Action, _>`;
///     factory wraps it into an `Action`-array generator with
///     stateful-guard filtering.
///   - `actionSequence(forCaseIterable:length:statefulGuards:)` —
///     convenience for `Action: CaseIterable`. Internally builds the
///     per-action generator via PropertyBased's `Gen<Action>.case`
///     and delegates to the primary entry.
public enum ActionSequenceFactory {

    /// Default sequence-length range. The v2.0 PRD §8.1 default is
    /// `0...16`; tighter than QuickCheck's typical `0...100` because
    /// reducer state grows monotonically and longer sequences are
    /// harder to shrink to a minimal failing trace. Calibration
    /// cycles may revise.
    public static let defaultLength: ClosedRange<Int> = 0...16

    /// **Primary entry — carrier-agnostic.** Wraps `actionGen` into
    /// an `Action`-array generator whose elements are filtered
    /// through each `StatefulGuard` in left-to-right order. When the
    /// guard list is empty, this delegates to PropertyBased's
    /// existing `Generator.array(of:)` (no overhead).
    ///
    /// **Filtering semantics.** For each candidate action drawn from
    /// `actionGen.array(of:length)`, every guard's
    /// `wouldAllow(_:given:)` is consulted with the *already-accepted*
    /// history. If all guards accept, the action is appended; if any
    /// rejects, the action is dropped. The result is `≤ length` actions
    /// and always satisfies every guard by construction. Per-sequence
    /// rejection (re-roll the whole sequence on any rejection) would
    /// loop forever under restrictive guards — see `StatefulGuard` doc.
    public static func actionSequence<Action: Sendable, ShrinkSeq>(
        from actionGen: Generator<Action, ShrinkSeq>,
        length: ClosedRange<Int> = defaultLength,
        statefulGuards: [any StatefulGuard<Action>] = []
    ) -> Generator<[Action], some SendableSequenceType> {
        let base = actionGen.array(of: length)
        if statefulGuards.isEmpty {
            return base
        }
        return base.map { candidates in
            applyGuards(candidates, statefulGuards: statefulGuards)
        }
    }

    /// **Convenience entry — `Action: CaseIterable`.** Builds a
    /// uniform per-case `Generator<Action, _>` via PropertyBased's
    /// `Gen<Action>.case` and delegates to the primary entry.
    ///
    /// Action enums with payload-carrying cases are *not* derivable
    /// here — `Gen<Action>.case` requires `CaseIterable`, which Swift
    /// only synthesizes for payload-free enums. Consumers with
    /// payload-carrying actions must construct their own
    /// `Generator<Action, _>` and call the primary entry. The
    /// v2.0 PRD §16 #4 "no silently-wrong code" hard guarantee is
    /// preserved: the absence of derivation surfaces as a missing
    /// `CaseIterable` conformance at the call site, not a hidden
    /// `.todo`-stubbed generator.
    public static func actionSequence<Action: CaseIterable & Sendable>(
        forCaseIterable _: Action.Type,
        length: ClosedRange<Int> = defaultLength,
        statefulGuards: [any StatefulGuard<Action>] = []
    ) -> Generator<[Action], some SendableSequenceType>
    where Action.AllCases: Sendable {
        actionSequence(
            from: Gen<Action>.case,
            length: length,
            statefulGuards: statefulGuards
        )
    }

    // MARK: - Internals

    /// Walk candidate actions left-to-right, retaining only those
    /// where every guard returns `true` against the
    /// already-accepted history. Pure; testable in isolation.
    static func applyGuards<Action>(
        _ candidates: [Action],
        statefulGuards: [any StatefulGuard<Action>]
    ) -> [Action] {
        var accepted: [Action] = []
        for candidate in candidates {
            let allowed = statefulGuards.allSatisfy { rule in
                rule.wouldAllow(candidate, given: accepted)
            }
            if allowed {
                accepted.append(candidate)
            }
        }
        return accepted
    }
}
