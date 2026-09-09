# Mutation / regression corpus (private)

A hand-authored mutant corpus for **sharpening the law kit itself** (Chapter 30
§30.4.4). Each mutant forces one law's property to always-true — so the law stops
detecting the very violation it exists to catch — and the corresponding
`PlantedBugs/` detection test (which expects that violation) fails. This is the
framework self-test gate, turned into a standing regression corpus. Not a scored
benchmark — no frozen answer key.

Each mutant is a reversible patch (`patches/<id>.patch`). The runner applies one,
builds, runs its named killer test via `swift test --filter`, checks the outcome,
and reverts.

## Run

```sh
mutants/run-mutants.sh                              # all mutants
mutants/run-mutants.sh semigroup-associativity-always-holds
```

Requires a clean working tree.

## The corpus (`manifest.json`)

| id | shape | expected | killer (planted-bug test) |
|---|---|---|---|
| `semigroup-associativity-always-holds` | law-detection | killed | `detectsNonAssociativeCombine` |
| `equatable-transitivity-always-holds` | law-detection | killed | `detectsNonTransitiveEquality` |
| `monoid-left-identity-always-holds` | law-detection | killed | `detectsBadLeftIdentity` |
| `equatable-symmetry-always-holds` | law-detection | killed | `detectsSymmetryOnlyEquality` |
| `product-orders-row-major` | enumeration-machinery | killed | `productWalkMatchesABruteForceSummedSizeOrdering` |
| `prefix-forgets-full-count` | enumeration-machinery | killed | `prefixTruncatesButRemembersTheFullSpace` |
| `walk-does-not-stop-at-first-failure` | enumeration-machinery | killed | `aWalkStopsAtTheFirstFailure` |
| `map-collapses-size-buckets` | enumeration-machinery | killed | `mapKeepsOrderSizesAndAddresses` |
| `formatter-offers-a-seed-for-a-walk` | enumeration-machinery | killed | `aCompleteWalkSaysSoAndOffersNoSeed` |
| `coverage-complete-off-by-one` | enumeration-machinery | killed | `coverageIsCompleteOnlyWhenEveryCaseWasSeen` |
| `vacuity-ignores-a-complete-walk` | enumeration-machinery | killed | `vacuityMessageDistinguishesItsTwoCauses` |
| `enumerated-ternary-degenerates-to-pairs` | enumeration-machinery | killed | `walkedSuiteReportsCoverage` |
| `enumerated-failure-drops-the-law-message` | enumeration-machinery | killed | `walkedCounterexampleCarriesBothHalves` |
| `walked-chain-drops-inherited-laws` | algebraic-walk | killed | `groupWalkChainsInherited` |
| `semilattice-chains-to-the-wrong-parent` | algebraic-walk | killed | `semilatticeWalkChainsWholeCluster` |
| `walked-ring-drops-right-distributivity` | algebraic-walk | killed | `ringWalkCoversEveryLaw` |
| `layout-space-never-prepends` | space-sampling | killed | `layoutSpaceReachesWrappedBuffers` |
| `layout-space-loses-its-size-ordering` | space-sampling | killed | `layoutSpaceIsSmallestFirst` |
| `bridge-draws-from-a-truncated-range` | space-sampling | killed | `theBridgeReachesMostOfASmallSpace` |

The first four blind a Strict-tier law by making its `property:` closure return
`true` unconditionally; the planted violator sails through, and the detection
test that demanded it be caught goes red. All four verified killed.

**The `enumeration-machinery` shape is different, and deliberately so.** A law
mutant asks *does the suite still catch this bug?* A machinery mutant asks *does
the harness still tell the truth about what it did?* — which is the failure mode
`SpaceCoverage` exists to prevent, and it does not show up as an uncaught
violator. Four of the six degrade a **claim** rather than a check:
`prefix-forgets-full-count` makes a truncated walk report complete coverage,
`coverage-complete-off-by-one` makes a complete walk deny it,
`formatter-offers-a-seed-for-a-walk` hands back a replay handle that means
nothing, and `map-collapses-size-buckets` discards the ordering contract while
every case still walks. Each leaves the suite green in every other respect. The
other two, `product-orders-row-major` and
`walk-does-not-stop-at-first-failure`, take away minimality — the first failure
found stops being the smallest failure that exists — which is the property the
whole design turns on and which no assertion about pass/fail would notice.
All six verified killed.

**`algebraic-walk` is a third shape, and it targets the chain rather than a
law.** Each of the six algebraic suites now has a sampled and a walked entry
delegating to one assembler, and the risk that shape carries is that the two
stop agreeing about *which laws run*. All three mutants leave every law passing
and every result reporting a complete walk, while quietly changing the set:
`.all` and `.ownOnly` swapped, a chain that skips `CommutativeMonoid`, and a
Ring that runs left-distributivity twice and right-distributivity never. The
last is the reason `ringWalkCoversEveryLaw` asserts law *names* — the result
count is still eleven.

**A gap this corpus found — and we then closed.** Blinding `Equatable.symmetry`
originally *survived*: the only asymmetric planted violator
(`PriorityCompareEquatable`, whose `==` is `>`) also breaks reflexivity, and
`detectsAsymmetricEquality` asserts merely "some `Equatable.` law," so reflexivity
kept catching it — the symmetry arm was never independently pinned. The fix added
`SymmetryOnlyEquatable` (a `>=` type that is reflexive, transitive, and
negation-consistent, so symmetry is its *only* broken law) and
`detectsSymmetryOnlyEquality`, which asserts the specific `Equatable.symmetry`
violation. With those in place the symmetry mutant is caught — the mutation suite
exposing a law arm that no test pinned, and driving the fix.

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json`.

**`space-sampling` is a fourth shape, and it guards a claim no law can make.**
A space's value is that it reaches configurations a construction-path generator
never produces — and nothing about a passing law says whether that happened.
`layout-space-never-prepends` is the sharpest of the corpus for that reason:
`DequeLayouts` still enumerates 107 arrangements, still reports its size, still
drives every `Deque` law to a pass — and builds every one of them by appending,
so the head never moves and not one is wrapped. It closes exactly nothing while
looking identical to the version that closes the gap. Only a test that measures
the wrapped fraction can tell them apart.
