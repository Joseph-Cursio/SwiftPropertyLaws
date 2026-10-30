# Validation findings (PRD §8)

PRD §8's external validation gate has three passes. Pass 1 scans real packages with the discovery tool, Pass 2 runs the kit's law checks against external types, and Pass 3 searches package histories for bugs the kit should have caught. This file records what each pass found and how to rerun it.

**All three passes were last run on 2026-10-29, with SwiftPropertyLaws at `de77415`.** Passes 2 and 3 need Swift 6.3 or earlier; see [Running Passes 2 and 3](#running-passes-2-and-3).

## Pass 1: discovery scan

`Validation/run.sh` runs `PropertyLawDiscoveryTool` over one target's sources and writes the generated file and the tool's summary to `Validation/results/<Target>.{generated.swift,summary.txt}`. It does not add the kit to the scanned package and does not run any law check. It shows that the tool handles code its authors didn't write: no crashes, output that parses, the most-specific dedupe, and a `.todo` list that names every type needing a hand-written `gen()`.

| Package | Scanned at | Source files | Types detected | Skipped, no suite | Suites | Checks | Derived generator | `.todo` |
|---|---|---|---|---|---|---|---|---|
| `swift-argument-parser` (`ArgumentParser`) | `1.8.2-39-gefd239f` | 52 | 131 | 11 | 27 | 34 | 29 | 5 |
| `Hummingbird` (`Hummingbird`) | `2.27.0-1-g0806106` | 75 | 139 | 35 | 18 | 21 | 10 | 11 |
| `swift-aws-lambda-runtime` (`AWSLambdaRuntime`) | `3.0.2` | 43 | 38 | 12 | 9 | 11 | 6 | 5 |
| `Sitrep` (`SitrepCore`) | `4.0.0-4-gae446f9` | 12 | 16 | 12 | 0 | 0 | 0 | 0 |
| **Total** | | **182** | **324** | **70** | **54** | **66** | **45** | **21** |

"Checks" counts emitted `@Test` methods, one per protocol that survives the most-specific dedupe. A check whose generator did not derive carries the deliberate `.todo` that does not compile (PRD §5.7). Each of the three non-empty files has at least one, so none of them compiles until those types get a `gen()`. All four files parse (`swiftc -parse`).

### What the checks cover

- **ArgumentParser:** 19 Hashable, 7 Equatable, 5 Comparable (`Name`, `InputOrigin.Element` and the `SplitArguments` index types), 2 RawRepresentable (`CompletionShell`, `SplitArguments.InputIndex`), and 1 RandomAccessCollection (`ArgumentSet`, which runs the whole collection chain).
- **Hummingbird:** 11 Equatable, 4 Hashable, 2 RawRepresentable (`MediaType.Category`, `MediaType.FileExtension`), 2 Sequence (the two split-string sequences), 1 Collection (`RouterPath`) and 1 Codable (`MediaType`).
- **AWSLambdaRuntime:** 6 Codable (`ClientApplication`, `ClientContext`, `ErrorResponse`, `JSONLogHandler.LogEntry`, `LambdaRequestID`, `StreamingLambdaStatusAndHeadersResponse`) and 5 Hashable.
- **SitrepCore:** none. Every detected type is skipped or has no stdlib conformance the kit checks.

### Why 70 types get no suite

The tool detects a type and then declines to emit its suite when the suite could not compile:

- **26 are `private` or `fileprivate`**, so they can't be named from the generated file. Most are synthesized `CodingKeys` enums.
- **44 are `public` with no `Sendable` conformance the tool can see.** Swift infers `Sendable` only for non-public types, and every check requires it.

**Finding: 11 of those 44 are `Sendable` after all.** The tool's set of protocols that refine `Sendable` is computed from the scanned module alone, so it misses the ones the standard library declares:

- **`Error`**: `ExitCode`, `CleanExit` and `ValidationError` in ArgumentParser, and `Cookie.ValidationError`, `Environment.Error`, `PersistError`, `RouterValidationError` and `URLEncodedFormError` in Hummingbird.
- **`Clock` and `InstantProtocol`**: `LambdaClock` and `LambdaClock.Instant` in AWSLambdaRuntime.
- **An actor**, which is always `Sendable`: Hummingbird's `MemoryPersistDriver`.

Suites for these types would have compiled. Pass 2 runs `checkHashablePropertyLaws` against `ExitCode`, which compiles only because `ExitCode: Error` makes it `Sendable`. This is a coverage loss, not a correctness one: the tool errs toward skipping. It is not fixed here.

The other 33 skips are correct. SitrepCore's nine are public `Codable` structs with no `Sendable` at all, and ArgumentParser's property wrappers are `Sendable` only conditionally (`extension Flag: Sendable where Value: Sendable`).

### Where generators fail to derive

204 detected types would need a hand-written `gen()`, most of them types that get no check anyway. The two largest buckets:

- **75 are "declaration not in this target".** That is an artifact of how `run.sh` scans: it passes one target's files and no `--context-files`, so a type the target only extends looks undeclared. The discovery plugin passes dependency sources as context automatically.
- **61 have a user-defined `init`** that no tier could call with derivable arguments.

The full breakdown per package is at the top of each `.summary.txt`.

### Rerun Pass 1

```bash
Validation/run.sh ~/xcode_projects/swift-argument-parser ArgumentParser
Validation/run.sh ~/xcode_projects/Hummingbird Hummingbird
Validation/run.sh ~/xcode_projects/swift-aws-lambda-runtime AWSLambdaRuntime
Validation/run.sh ~/xcode_projects/Sitrep SitrepCore
git diff Validation/results/
```

`run.sh` builds the tool in release mode first. Record the scanned revision of each package in the table above. The results are only comparable between runs at the same upstream revision.

## Pass 2: law checks against external code

`Validation/Package.swift` is a separate SwiftPM package. It depends on the kit by local path and on the external packages by URL, so no consumer of `SwiftPropertyLaws` ever sees those dependencies. Each test writes a generator for an external type and calls a `check…PropertyLaws` suite on it.

| Test file | Type | Suite | Suppressions | Result |
|---|---|---|---|---|
| `ExternalPackageTests` | `ArgumentParser.ExitCode` | Hashable (full chain) | `Hashable.distribution` (skipped) | passed |
| | `ArgumentParser.ExitCode` | RawRepresentable | none | passed |
| | `ArgumentParser.ArgumentVisibility` | Hashable (full chain) | `Hashable.distribution` (skipped) | passed |
| | `ArgumentParser.CompletionShell` | RawRepresentable | none | passed |
| `StdlibNumericLawsTests` | `Int32` | FixedWidthInteger (with BinaryInteger, Numeric, AdditiveArithmetic), SignedInteger | none | passed |
| | `UInt` | FixedWidthInteger, UnsignedInteger | none | passed |
| | `Double` | BinaryFloatingPoint, finite-only and with NaN (`allowNaN: true`) | none | passed |
| `StdlibStringProtocolLawsTests` | `String`, `Substring` | StringProtocol | none | passed |
| `BigIntLawsTests` | `BigInt` | BinaryInteger, SignedInteger | none | passed |
| | `BigUInt` | BinaryInteger, UnsignedInteger | `bitwiseDoubleNegation`, `bitwiseDeMorgan` | passed with documented exceptions |
| `DecimalLawsTests` | `Foundation.Decimal` | SignedNumeric, Numeric (own), AdditiveArithmetic | none | passed |
| `ComplexLawsTests` | `Complex<Double>` | Numeric (own) | `additionAssociativity`, `multiplicationAssociativity`, `leftDistributivity`, `rightDistributivity`, `subtractionInverse` | passed with documented exceptions |
| | `Complex<Double>` | SignedNumeric (own) | none | passed |

That is 21 law-suite tests, all at `.standard` (1,000 trials), plus `complexCommutativityIsExactOnNonFiniteInputs`, a plain assertion that `Complex` addition and multiplication commute exactly even on non-finite values. All 22 pass, as do Pass 3's two, on both Swift 6.2.4 and Swift 6.3.3.

### Why two Hashable checks skip `Hashable.distribution`

`Hashable.distribution` is the Heuristic law that fails when fewer than 10% of the draws produce distinct hash values. `ArgumentVisibility` has exactly three values, and the `ExitCode` generator draws from ten fixed codes, so 1,000 draws can give at most 3 and 10 distinct hashes. The ratio is capped by the size of the domain, not by the quality of the hash, so the law is skipped for these two types, with that reason recorded. Every Strict Hashable and Equatable law still runs on both.

**These two tests used to pass only because the kit was silent.** Until `6025bd6` (2026-07-13), a Conventional or Heuristic violation under `.default` was dropped without a word, so this one went unseen. Now it is recorded: as a warning on Swift 6.3 and later, and as an error that fails the test on Swift 6.2, where Swift Testing has no warning severity. On 6.2.4 the two tests failed until the law was skipped. The heuristic has no notion of a small domain, so any closed-set type will trip it the same way.

### Finding: `BigUInt`'s bitwise NOT does not satisfy De Morgan's law

`BigUInt` stores its value as a word array whose length depends on the value. `~BigUInt(0)` is `0`, while `~x` for a non-zero `x` flips a whole 64-bit word. So `~(x & y)` and `~x | ~y` can disagree:

```
x = 406803, y = 51776           (replay seed JJV3lDSZMUfh1OXBSpPuu+SMxMVOzze42idwOvk3nK4=)
x & y     = 0
~(x & y)  = 0
~x | ~y   = 18446744073709551615 (= UInt64.max)
```

`~~x == x` fails for the same reason. Signed `BigInt` is unaffected, because its `~x` is `-(x + 1)`, which does not depend on storage. The two laws are suppressed as `intentionalViolation` with their reasons recorded. A regression in any *other* law would still fail. The full write-up is [`findings/BigUInt-bitwise-divergence.md`](findings/BigUInt-bitwise-divergence.md).

### `Complex<Double>` needs its rounding laws suppressed

Its components are `Double`, so chained arithmetic rounds the way `Double`'s does, and the exact-equality associativity, distributivity and subtraction-inverse laws fail under random sampling. That is rounding, not a bug in `Complex`. These laws fail by unbounded amounts under cancellation, so no equivalence oracle rescues them, and suppression is the answer. Commutativity is exact, and it stays checked.

### What Pass 2 shows

The kit composes with external SwiftPM packages, and its Strict laws run end to end against types its authors didn't write, stdlib reference implementations included. One run found a genuine divergence (`BigUInt`). The rest found the laws holding, which is the expected result for heavily tested code.

## Pass 3: git archaeology

Pass 3 searches the history of popular packages for commits that fix what looks like a protocol-law violation, then checks out the parent of the fix and asks whether the kit would have caught it.

### Survey

Five full-history packages, about 6,400 commits in all:

| Package | Commits | Conformance fixes worth inspecting |
|---|---|---|
| `swift-argument-parser` | 515 | 0 (synthesized conformances; parser and decoder bugs only) |
| `swift-aws-lambda-runtime` | 434 | 0 (correct on arrival; no patches) |
| `swift-collections` | 1,873 | 1 candidate (`35349601`) |
| `swift-nio` | 2,605 | 0 (internal types or non-law methods) |
| `hummingbird` | 973 | 0 (small Codable surface) |

The search ran `git log --grep="hash|equ|codable|encode|decode|comparable|round.?trip|symmet|transit|consist"` and inspected the diff of every promising hit. The common reasons for rejecting a hit:

- It *added* a missing conformance rather than fixing one.
- The bug was in an `internal` or `fileprivate` type, with no public surface to test.
- It was in a custom `KeyedDecodingContainerProtocol`, which is decoder internals rather than a value type's `init(from:)` or `encode(to:)`.
- It was a refactor that preserved semantics.
- It was in a user-named method (such as `BitSet.isEqualSet(to:)`) rather than the protocol's `==`, `hash(into:)`, `<` or Codable round trip.

### The candidate: `swift-collections@35349601`

> "Typo: symmetric difference should be the xor, not intersection. Otherwise it is the same as the intersection."

```diff
- internal func symmetricDifference(_ other: Self) -> Self {
-   Self(_value: _value & other._value)
- }
+ internal func symmetricDifference(_ other: Self) -> Self {
+   Self(_value: _value ^ other._value)
+ }
```

The fix was on a method `SetAlgebra` requires, behind a public type (`TreeSet`), and its message names a real algebraic violation.

**It exposed a gap in the kit.** At the time, the SetAlgebra suite had five laws and none of them exercised `symmetricDifference`. Four were added (`symmetricDifferenceSelfIsEmpty`, `symmetricDifferenceEmptyIdentity`, `symmetricDifferenceCommutativity`, `symmetricDifferenceDefinition`), guarded by a `BuggySymmetricDifference` planted bug that returns the intersection. The suite has since grown to 19 laws (PRD §4.3).

### What Pass 3 found

`ValidationPass3Tests` pins `swift-collections` to `8e5e4a8f`, the parent of the fix, with the buggy `_Bitmap.symmetricDifference` in place. **`TreeSet<Int>` passes every SetAlgebra law there**, and Apple's own regression input (`[1, 3]` △ `[2, 3]`) also gives the correct `[1, 2]`.

The reason is that the buggy method is dead code. `TreeSet.symmetricDifference` dispatches through `_HashNode._symmetricDifference` to the `_symmetricDifference_slow*` paths, which build the result by structural traversal. Nothing calls `_Bitmap.symmetricDifference`. Apple's commit fixed a real typo on sight, but in unreachable code. The test asserts what is true: the kit reports no violation at the buggy SHA, so it does not false-positive on dead code. If `swift-collections` ever routes a public path through that method, `treeSetPassesAllLawsAtBuggySHA` will start failing, and the pin should be re-evaluated.

### What it means

Across about 6,400 commits, one candidate survived filtering, and it was not observable through the public API. Well-tested Swift packages lean on synthesized conformances, and their hand-written conformances tend to land correct. That leaves almost no historical kit-detectable bugs to find. This evidence is why PRD §8 measures the gate by these three passes rather than by a quota of bugs caught. The kit's value is *prevention*, catching a broken conformance as it is written, not retroactive discovery.

## Running Passes 2 and 3

On Swift 6.4, `cd Validation && swift test` fails before compiling anything. Pass 3 needs `swift-collections` at exactly `8e5e4a8f`, and the package pins it by revision. That revision's manifest declares no traits (`traits: [], //_traits`), yet one of its build settings is conditioned on the trait `UnstableSortedCollections`. The Swift 6.4 package manager rejects this:

```
error: 'swift-collections': Trait 'UnstableSortedCollections' referenced in the build settings condition for target '…' is not defined in the package
```

The pin applies to the whole package, so Pass 2 fails with it, even though Pass 2 never uses `swift-collections`.

Swift 6.3.3 and 6.2.4 accept the manifest. But neither can compile a package manifest against Xcode 27's macOS 27.0 SDK (`unknown argument: '-target-arch-variant'`), so they need an older SDK. The Command Line Tools ship the macOS 26.5 SDK, and that combination works:

```bash
cd Validation
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swiftly run swift test +6.3.3
```

Add `--filter SwiftCollectionsRetroactiveTests` for Pass 3 alone. Use `+6.3.3` rather than `+6.2.4` when you have the choice: Swift 6.2 has no warning severity, so it fails a test over a Heuristic violation that 6.3 only reports. Neither pass runs in CI.

Moving Pass 3 into its own package would let Pass 2 build on Swift 6.4 again. That hasn't been done.
