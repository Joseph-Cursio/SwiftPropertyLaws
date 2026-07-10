import DequeModule
import PropertyBased
import PropertyLawKit

/// Laws for `Deque`'s double-ended surface (Phase 1 M3 of the
/// collections/async workplan). The protocol chains (M1) already cover
/// Deque-as-RangeReplaceableCollection; what they can't see is the front
/// end — `prepend`/`popFirst` have no protocol home, so they get mirror
/// laws of the append side plus an array-model agreement law:
///
/// - `prependPopFirstRoundTrips` — prepending a value then `popFirst()`
///   returns it and restores the original deque.
/// - `appendPopLastRoundTrips` — the back-end mirror.
/// - `arrayModelRoundTrip` — `Deque(Array(deque)) == deque`: a deque is
///   observationally its array model.
///
/// Stated over the concrete `Deque<Element>` (no double-ended protocol
/// exists to abstract over), so the planted-violator self-test gate doesn't
/// apply — these exercise swift-collections itself.
public enum DequeSymmetryLaw: String, Sendable, Hashable, CaseIterable {
    case prependPopFirstRoundTrips
    case appendPopLastRoundTrips
    case arrayModelRoundTrip
}

extension LawIdentifier {
    public static func dequeSymmetry(_ law: DequeSymmetryLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Deque", lawName: law.rawValue)
    }
}

@discardableResult
public func checkDequeSymmetryPropertyLaws<
    Element: Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for type: Deque<Element>.Type = Deque<Element>.self,
    using generator: Generator<Deque<Element>, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkPrependPopFirstRoundTrips(generator: generator, options: options),
            await checkAppendPopLastRoundTrips(generator: generator, options: options),
            await checkArrayModelRoundTrip(generator: generator, options: options)
        ]
    }
}

private func checkPrependPopFirstRoundTrips<
    Element: Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Deque<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Deque.prependPopFirstRoundTrips",
        generator: generator,
        options: options,
        property: { deque in
            // The probe value is the deque's own first element; the empty
            // deque passes vacuously (no element to reuse — Element is
            // generic, so the law can't invent one).
            guard let probe = deque.first else { return true }
            var copy = deque
            copy.prepend(probe)
            return copy.popFirst() == probe && copy == deque
        },
        formatCounterexample: { deque, _ in
            "deque = \(deque); prepend(first) then popFirst() did not "
                + "restore the original"
        }
    )
}

private func checkAppendPopLastRoundTrips<
    Element: Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Deque<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Deque.appendPopLastRoundTrips",
        generator: generator,
        options: options,
        property: { deque in
            guard let probe = deque.last else { return true }
            var copy = deque
            copy.append(probe)
            return copy.popLast() == probe && copy == deque
        },
        formatCounterexample: { deque, _ in
            "deque = \(deque); append(last) then popLast() did not "
                + "restore the original"
        }
    )
}

private func checkArrayModelRoundTrip<
    Element: Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<Deque<Element>, Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "Deque.arrayModelRoundTrip",
        generator: generator,
        options: options,
        property: { deque in Deque(Array(deque)) == deque },
        formatCounterexample: { deque, _ in
            "deque = \(deque); Deque(Array(deque)) = \(Deque(Array(deque)))"
        }
    )
}
