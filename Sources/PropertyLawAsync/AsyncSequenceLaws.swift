import AsyncAlgorithms
import PropertyBased
import PropertyLawKit

/// Checks the clock-free `AsyncSequence` laws over values drawn from `generator`.
///
/// Each sample is a source array, lifted to an async sequence per law with `.async`. The
/// laws compare swift-async-algorithms' `chunks`, `adjacentPairs`, `removeDuplicates`,
/// `interspersed`, `compacted`, `merge` and `zip` against synchronous models, and check
/// that an exhausted iterator stays exhausted.
///
/// - Parameters:
///   - generator: The values to check the laws against.
///   - options: The budget, enforcement and suppressions for the run.
/// - Returns: One result per law.
/// - Throws: `PropertyLawViolation` when a law fails at a tier `options.enforcement` escalates.
@discardableResult
public func checkAsyncSequencePropertyLaws<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    for _: [Element].Type = [Element].self,
    using generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions = LawCheckOptions()
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await checkChunksMatchSyncModel(generator: generator, options: options),
            await checkChunksConcatenation(generator: generator, options: options),
            await checkAdjacentPairs(generator: generator, options: options),
            await checkRemoveDuplicates(generator: generator, options: options),
            await checkInterspersed(generator: generator, options: options),
            await checkCompacted(generator: generator, options: options),
            await checkMergeMultiset(generator: generator, options: options),
            await checkZipMatchesSyncZip(generator: generator, options: options),
            await checkIteratorStaysExhausted(generator: generator, options: options),
        ]
    }
}

/// Drain a finite async sequence into an array.
func collect<Source: AsyncSequence>(_ source: Source) async rethrows -> [Source.Element] {
    var collected: [Source.Element] = []
    for try await element in source { collected.append(element) }
    return collected
}

private func checkChunksMatchSyncModel<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.chunksMatchSyncModel",
        generator: generator,
        options: options,
        property: { sample in
            let size = sample.count % 4 + 1
            let chunked = try await collect(sample.async.chunks(ofCount: size))
            return chunked == syncChunks(sample, size: size)
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); async chunks(ofCount:) diverged from the sync model"
        }
    )
}

private func checkChunksConcatenation<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.chunksConcatenationRestoresSource",
        generator: generator,
        options: options,
        property: { sample in
            let size = sample.count % 4 + 1
            let chunked = try await collect(sample.async.chunks(ofCount: size))
            return chunked.flatMap(\.self) == sample
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); concatenating the chunks did not restore the source"
        }
    )
}

private func checkAdjacentPairs<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.adjacentPairsMatchSyncModel",
        generator: generator,
        options: options,
        property: { sample in
            let pairs = try await collect(sample.async.adjacentPairs())
            let model = Array(zip(sample, sample.dropFirst()))
            return pairs.count == model.count
                && zip(pairs, model).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); adjacentPairs() diverged from zip(x, x.dropFirst())"
        }
    )
}

private func checkRemoveDuplicates<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.removeDuplicatesMatchesSyncModel",
        generator: generator,
        options: options,
        property: { sample in
            let deduplicated = try await collect(sample.async.removeDuplicates())
            return deduplicated == syncRemoveConsecutiveDuplicates(sample)
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); removeDuplicates() diverged from the "
                + "consecutive-dedup sync model"
        }
    )
}

private func checkInterspersed<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.interspersedMatchesSyncModel",
        generator: generator,
        options: options,
        property: { sample in
            // Separator derived from the sample (generic Element); the empty
            // source passes vacuously — there is no element to intersperse
            // with and no separator to derive.
            guard let separator = sample.first else { return true }
            let interspersed = try await collect(sample.async.interspersed(with: separator))
            return interspersed == syncInterspersed(sample, separator: separator)
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); interspersed(with: first) diverged from the sync model"
        }
    )
}

private func checkCompacted<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.compactedMatchesCompactMap",
        generator: generator,
        options: options,
        property: { sample in
            // Optional injection derived by position, keeping the sampled
            // seed the only randomness.
            let optionals: [Element?] = sample.enumerated().map { pair in
                pair.offset.isMultiple(of: 3) ? nil : pair.element
            }
            let compacted = try await collect(optionals.async.compacted())
            return compacted == optionals.compactMap(\.self)
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); compacted() diverged from compactMap { $0 }"
        }
    )
}

// MARK: - Sync models

private func syncChunks<Element>(_ source: [Element], size: Int) -> [[Element]] {
    guard size > 0 else { return [] }
    return stride(from: 0, to: source.count, by: size).map { start in
        Array(source[start ..< Swift.min(start + size, source.count)])
    }
}

private func syncRemoveConsecutiveDuplicates<Element: Equatable>(_ source: [Element]) -> [Element] {
    var result: [Element] = []
    for element in source where element != result.last {
        result.append(element)
    }
    return result
}

private func syncInterspersed<Element>(_ source: [Element], separator: Element) -> [Element] {
    var result: [Element] = []
    for element in source {
        if result.isEmpty == false { result.append(separator) }
        result.append(element)
    }
    return result
}
