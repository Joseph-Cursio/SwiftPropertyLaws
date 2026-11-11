import DequeModule
import PropertyBased
import PropertyLawKit

/// Checks the `Deque` front-end symmetry laws over values drawn from `generator`.
///
/// `prepend` / `popFirst` and `append` / `popLast` must round-trip, and a deque must
/// agree with an array model. The front end has no protocol of its own, so
/// `RangeReplaceableCollection`'s laws do not reach it.
///
/// - Parameters:
///   - generator: The values to check the laws against.
///   - options: The budget, enforcement and suppressions for the run.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkDequeSymmetryPropertyLaws<
    Element: Equatable & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: Deque<Element>.Type = Deque<Element>.self,
    using generator: Generator<Deque<Element>, Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkPrependPopFirstRoundTrips(generator: generator, options: options),
            await checkAppendPopLastRoundTrips(generator: generator, options: options),
            await checkArrayModelRoundTrip(generator: generator, options: options),
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
