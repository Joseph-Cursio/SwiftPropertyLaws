import AsyncAlgorithms
import PropertyBased
import PropertyLawKit

// The order-insensitive and termination laws of the AsyncSequence family
// (see AsyncSequenceLaws.swift for the family header). Split into its own
// file to respect the file-length lint cap, mirroring the planted-violator
// split precedent.

func checkMergeMultiset<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "AsyncSequence.mergePreservesElementMultiset",
        generator: generator,
        options: options,
        property: { first, second in
            // merge's interleaving is scheduler-dependent; the multiset
            // (sorted collection) is the equivalence under which it is
            // deterministic. Comparing sorted output against the sorted
            // concatenation asserts no element is dropped, invented, or
            // duplicated — while deliberately saying nothing about order.
            let merged = try await collect(merge(first.async, second.async))
            return merged.sorted() == (first + second).sorted()
        },
        formatCounterexample: { first, second, _ in
            "a = \(first), b = \(second); merge(a, b) lost or invented elements "
                + "(multiset comparison after sorting)"
        }
    )
}

func checkZipMatchesSyncZip<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runBinaryLaw(
        "AsyncSequence.zipMatchesSyncZip",
        generator: generator,
        options: options,
        property: { first, second in
            // Unlike merge, zip IS order-deterministic: pairwise correspondence
            // and length (min of the inputs) match Swift.zip exactly.
            let zipped = try await collect(zip(first.async, second.async))
            let model = Array(Swift.zip(first, second))
            return zipped.count == Swift.min(first.count, second.count)
                && zipped.count == model.count
                && Swift.zip(zipped, model).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        },
        formatCounterexample: { first, second, _ in
            "a = \(first), b = \(second); zip(a, b) diverged from Swift.zip"
        }
    )
}

func checkIteratorStaysExhausted<
    Element: Comparable & Sendable,
    Shrinker: SendableSequenceType
>(
    generator: Generator<[Element], Shrinker>,
    options: LawCheckOptions
) async -> CheckResult {
    await runUnaryLaw(
        "AsyncSequence.asyncIteratorStaysExhausted",
        generator: generator,
        options: options,
        property: { sample in
            // The AsyncIteratorProtocol mirror of the sync suite's
            // terminationStability law: once next() returns nil, it keeps
            // returning nil. Exercised through a combinator pipeline so the
            // exhaustion behavior of the wrapper types is covered too.
            var iterator = sample.async.removeDuplicates().makeAsyncIterator()
            while try await iterator.next() != nil { continue }
            let afterFirstNil = try await iterator.next()
            let afterSecondNil = try await iterator.next()
            return afterFirstNil == nil && afterSecondNil == nil
        },
        formatCounterexample: { sample, _ in
            "source = \(sample); the exhausted async iterator yielded again "
                + "after returning nil"
        }
    )
}
