# Enumeration combinators — bounded input spaces for the kit

Assessment prompted by `pbt-book/planning/conformance-checkers.md` §"Extension directions"
item 5, which records the kit's lack of `withEvery` / `withEveryRange` / `withEverySubset` /
`withEveryPermutation` as "the largest gap between the two kits". Written 2026-09-08.

**This is not a port.** A first draft of this assessment was written as one, and reading it
back, roughly half its design decisions were justified by fidelity to `StdlibUnittest`
rather than by anything about this kit. Those justifications are gone, and taking them out
changed the recommendation — the slice order inverted, one combinator was cut, one was
added, and a fallback mechanism disappeared entirely. Apple's apparatus is the reason to
look; it is not the specification. The corrections are recorded in §"What the first draft
got wrong" rather than smoothed over, because the pattern there is the same one this
repo's notes keep finding.

Claims below are marked **measured** (a spike in this repo, described well enough to re-run)
or **reasoned** (designed, not built). Nothing is asserted without one of the two.

## Why bother: the gap is in our own shipped coverage

**Measured.** The note argues enumeration reaches "layouts random generation will not find".
Here it is stronger than that — the layouts are reached with probability **zero**, and the
example is our code, not Apple's.

`Sources/PropertyLawCollections/DequeGenerators.swift:18` is the kit's only `Deque` source:

```swift
Gen<Int>.int(in: -100 ... 100).array(of: count).map { Deque($0) }
```

A `Deque` built from an array lays its ring buffer out from slot 0. A `Deque` of identical
contents built by `prepend` wraps. `withContiguousStorageIfAvailable` distinguishes them —
offered for the first, withheld for the second — so this is not internal bookkeeping, it is
a branch `Sequence`'s own laws observe.

| construction path | draws | contiguous | wrapped |
|---|---|---|---|
| `Deque(array)` — the kit's generator | 1 000 | 1 000 | **0** |
| four `prepend`s, then two `append`s | 1 | 0 | 1 |

Every `Deque` law this kit ships runs against one ring-buffer layout, and no budget fixes
it: `.exhaustive(10_000)` draws ten thousand contiguous deques.

The weaker general version also has a number. Over a 1 024-case space (subsets of `0..<10`),
a `.standard` 1 000-trial run covered **636 cases, 62%** — 388 unreached, and none of them
reported as unreached. Enumeration's contribution there is the denominator, not the
coverage.

## What the kit should enumerate — derived from our laws, not Apple's

Apple's four combinators exist because their subject is `Collection` index arithmetic. Ours
is 39 protocols, and the spaces that pay are different ones. This list is what the menu
should be; only the first two have `StdlibUnittest` ancestors.

**Every triple of a small carrier.** `Semigroup.combineAssociativity`
(`SemigroupLaws.swift:43`) is a `runTernaryLaw` over three independent random draws. An
8-element carrier has 512 triples — enumerable outright, no sampling, no budget question,
no possibility of an unreached combination. The whole algebraic cluster (Semigroup, Monoid,
CommutativeMonoid, Group, Semilattice, Ring) has this shape, and every one of its laws is
universally quantified over a small number of variables. **This is the highest-value
application in the kit and it has no ancestor to port** — Apple's apparatus contains no
algebraic laws.

**Every pair within an equivalence class.** Apple's `checkEquatable` takes a hand-written
partition; the note's translation table maps that to "a hand-written generator", which
loses the point. Our `a == b` antecedent fires at roughly `1/poolSize`, and CLAUDE.md
records paying for exactly this in `PropertyLawSyntax` — sizing a node pool so the
Equatable laws are not close to vacuous. A partition-shaped space makes the antecedent fire
by construction. That is the general form of a fix we have already bought once, locally.

**Every action sequence up to length k.** `ActionSequenceFactory` samples `[Action]` over a
default length of `0...16`. Over three actions, sequences to length 16 number 64 570 081;
to length 4, 121. Enumerating short and sampling long is the right bargain for
interaction invariants — most reachable-state defects show up in short prefixes — and it
makes the reported counterexample minimal by construction rather than by shrinking.

**Every subrange / every subset of an index space.** The two that do carry over, for the
collection laws they were built for, and for `RangeReplaceable`'s `replaceSubrange` in
particular.

**Cut: `everyPermutation`.** It earns close to nothing across our law surface — no kit law
is quantified over orderings. Add it when a caller asks, not before.

## Shape: a space is an indexed value

```swift
public struct Enumeration<Element: Sendable>: Sendable {
    public let count: Int
    let build: @Sendable (Int) -> Element
    let describe: @Sendable (Int) -> String
    let size: @Sendable (Int) -> Int      // see §Ordering
}
```

Apple's combinators are callback-nested, which is why they need `TestContext`'s label
stack: the failing case is identified by a path through a call tree, so the path must be
accumulated as the tree is walked. Indexing computes the address instead, and the label
stack is simply not needed — which also removes the note's warning that "adding combinators
without that stack would give the coverage and lose the diagnosis."

**Measured: every combinator must be closed-form; none may materialise its cases.**
Verified for `everyRange` (length-ascending), `everySubset` (combinatorial-number-system
unranking, cardinality-ascending) and `everyPermutation` (factorial-number-system,
lexicographic) — each `O(n)` per lookup, `O(1)` memory, each checked to be a bijection onto
the space it claims. Getting this wrong is not subtle: a product of `everyPermutation(10)`
and `everySubset(16)` is 237 817 036 800 cases, ~24 TB to materialise, and with closed-form
unranking 1 000 random-access lookups into it take 2 ms. `Int` overflow on a product is a
real hazard and is detectable rather than silent (`multipliedReportingOverflow`); `12! × 2^40`
already overflows.

**Dropped: `withSome(maxSamples:)`.** Apple needs a sampling fallback because they have no
generator. We have a seeded engine with shrinking, replay, near-miss tracking and coverage
classification. A space too large to walk should **become a `Generator`** — the kit's
native idiom — rather than acquire a second, weaker sampler that reports none of that. This
removes a whole mechanism and one way for the two modes to drift.

## Ordering, and why neither of the obvious answers is right

Smallest-first is what makes the first failure minimal — the note's "minimal
counterexamples for free". Within one combinator it is obvious. Across a **product** it is
a real decision, and the candidates disagree.

**Measured.** With a failure region deliberately asymmetric across the factors (fires at an
empty range with a large subset, and at a longer range with a singleton subset):

| ordering | first failure reported | cost per lookup |
|---|---|---|
| row-major (lexicographic) | `range=0..<0 / subset=[0, 1, 2, 3]` | `O(1)` |
| diagonal (by index sum) | `range=0..<2 / subset=[0]` | piecewise closed-form |

**Reasoned: both are proxies, and the kit can afford the real thing.** "Smallest" to a
reader means smallest *case*, not smallest index — index-sum only approximates it, and
approximates it worse the less uniform the factors' size distributions are. If each space
carries `size(index)`, a product can order by **summed size** directly. The precompute for
that is a convolution of the two factors' **size histograms** — `O(n)` entries each, `O(n²)`
for the product — not of their case counts, which is what makes it affordable on a
238-billion-case space. Unranking is then: locate the size-total bucket by cumulative sum,
locate the `(sizeA, sizeB)` split within it, index row-major inside that rectangle, map back
through each factor's size-bucket offset.

**Shipped and measured.** `Every.product` orders by summed size, and
`EnumerationProductTests.productWalkMatchesABruteForceSummedSizeOrdering` checks the
closed-form unranking case-by-case against a materialised brute-force ordering — which is
the check this section asked for before the scheme was relied on.
`summedSizeOrderingIsNotRowMajorOrdering` pins the decision itself, so a change that
quietly reverted to row-major fails rather than passing as a reordering.

## Coverage should be a reported fact, which retires `.exhaustive`

`TrialBudget.exhaustive(10_000)` is a trial count. The first draft proposed a separate entry
point plus a corrected doc comment. Self-consistency asks for more than that, because
`.exhaustive` is our own instance of the defect CLAUDE.md keeps recording — **a default
presented as a guarantee**, sitting in the public API under a name that invites the belief
that coverage is handled. Bolting enumeration on beside it repeats the defect; making
coverage sayable retires it.

So: `CheckResult` should carry what the run actually covered — `covered 512 of 512 cases`
for an enumerated run, `1 000 trials` for a sampled one — with the same nil-versus-empty
discipline the kit already applies to `nearMisses` (a law that cannot know says `nil`, not
a fabricated denominator). `.exhaustive`'s doc comment should say plainly that it is a trial
count regardless of whether the rest of this ships.

`CheckResult.seed` is non-optional and a fully enumerated run has no seed. Not a blocker,
but it should be decided deliberately rather than defaulted into.

## The finding worth chasing: enumeration changes what the kit can say

The note's eleventh correction records a limit on its own idea — a vacuity guard reports a
*correct* comparator as defective, because "the generator never built this" and "this cannot
exist" both count zero. `StrictWeakOrderingLaws.swift:277` encodes exactly that: the guard
is on three laws and deliberately off `incomparabilityTransitivity`, with the comment that
the other three absences are "generator weaknesses rather than properties worth having."

**Reasoned.** Over a *fully enumerated bounded carrier*, generator weakness is impossible by
construction. Zero applications then means **this cannot exist** — unambiguously. That does
not merely let the guard go back on the fourth law; it converts a vacuous pass into a
provable statement about the comparator: *this comparator totally orders this carrier.*

That is the general form: enumeration changes what the kit is able to **say**, not only how
much it covers. Every conditional law in the kit currently has an antecedent whose
non-firing is uninterpretable. Over a bounded space it becomes a result. This should be
verified on `StrictWeakOrderingLaws` first, since it is the one place the ambiguity is
already written down.

## Slices

**Inverted from the first draft**, which put the `Generator` bridge first. The bridge's one
real cost — that the index must travel with the value and land in the caller's property
closure — is entirely an artifact of squeezing a space through the `Generator` seam. Own
the input source and the driver holds the index, the address is reported from there, and
the law's closure keeps receiving a bare `Element`.

**Measured, and it is why the bridge cannot come first.** `LawCheck.shrink` is value-level
and the kit deliberately never threads a `Generator` — the `PropertyBackend` closure seam is
the reason — so a bridged space's `Shrink.Integer` is *ignored*, and the value alone cannot
name a smaller case. Same space, same law ("cardinality < 3" over subsets of `0..<10`):

| bridge | counterexample | shrink steps |
|---|---|---|
| bare `Element` | `[0, 3, 4, 8, 9]` | 0 |
| index-carrying case | `#56 [0, 1, 2]` | 5 |

`[0, 1, 2]` is exactly the minimal witness. A driver that owns the index gets the second row
without putting the index in the caller's hands.

**Slice 1 — `Enumeration` + an enumeration driver. SHIPPED.** `Enumeration<Element>` +
`EnumerationBucket`, the constructors under the `Every` namespace, `EnumerationDriver`,
`SpaceCoverage`, and `checkEveryCase`. 39 tests; 6 mutants in a new
`enumeration-machinery` shape, 6 killed.

Three things came out differently from the proposal above.

- **The combinators are named `Every.elements` / `Every.ranges` / `Every.subsets` /
  `Every.triples` / `Every.product`,** not `every` / `everyRange` / `everySubset`.
  `Every.everySubset(of: 8)` stutters; the `withEvery` spelling is Apple's, where the
  combinator is a free function and the prefix is carrying the meaning. Under a namespace it
  is redundant.
- **The ordering contract is a value, not a convention.** `EnumerationBucket` — contiguous
  runs of equal size, ascending — is public, so a space *states* its order rather than
  being trusted to have one. The invariant is enforced in `init` and asserted directly on
  every constructor, because everything this type claims about minimality rests on it.
- **`checkEveryCase` takes no trial cap and has no hidden default.** Capping is explicit
  via `Enumeration.prefix(_:)`. A default cap would be the same defect as `.exhaustive` in a
  new place: coverage quietly bounded, under a name that reads like completeness.

**Slice 2 — the algebraic overloads. SHIPPED.** All six suites — Semigroup, Monoid,
CommutativeMonoid, Group, Semilattice, Ring — take `overEvery carrier:` beside `using
generator:`. The `InputSource` seam landed earlier, pulled forward by a flake in the
strict-weak-ordering suite; this is the application it was proposed for.

Each `check<X>PropertyLaws` is a pair of thin public entries delegating to one shared
`from source:` assembler, so **a walked suite cannot run a different set of laws from the
sampled one**. Inheritance chains through the assembler, so a walked `Group` walks
`Monoid`'s and `Semigroup`'s laws rather than silently sampling them. The 18 private law
helpers are written once.

**The payoff, measured.** `RarelyNonAssociative` is addition modulo 32 with one anomalous
pair, `combine(29, 27) = 1`. One bad pair breaks associativity only for the triples routed
through it — **122 of 32 768**, brute-forced in a test so the number cannot drift. At that
density a sampled run misses the defect **69% of the time at `.sanity`** and 2.4% at
`.standard`: a CI flake, not a failure. The walk finds it every time and reports
`value=1 / value=28 / value=27`, the smallest triple that proves it, with no shrinker.

No probabilistic assertion was written — the density is pinned and the miss-rate follows
arithmetically, so no test depends on a distribution.

Mutation-tested: 3 mutants in a new `algebraic-walk` shape, 3 killed, plus one existing
patch regenerated. The Ring mutant did not die at first: the test asserted
`results.count == 11`, and a suite running one law twice and another never is still eleven
results. It now asserts law names.

**Slice 3 — the `Generator` bridge.** *(Not shipped.)* `Gen<Int>.int(in: 0 ..< count).map { space[$0] }` is a
`Generator<Element, Shrink.Integer<Int>>` and drives every existing entry point unchanged —
**measured** against `checkEquatablePropertyLaws`. Now framed correctly: not a compatibility
shim, but the honest fallback for a space too large to walk, and the thing that closes the
`Deque`-layout gap without touching any of the kit's 48 signatures. Callers accept that it
samples and does not shrink.

**Slice 4 — carrier enumeration around existing suites.** *(Not shipped.)* Enumerate carriers outside, run an
existing suite on each. Needs no per-protocol overloads. It does need a documented budget
convention, because 6 layouts × 1 000 trials × N laws is not what a caller expects from one
call — Apple avoids this because their inner checkers are deterministic and ours sample.

## What was not verified

*(Updated after Slice 1 shipped. Summed-size ordering moved out of this list — it is now
built and checked against brute force.)*

- No enumerated law was run against a real violator. The `% 8` index violator in the note is
  Apple's, in Apple's harness; nothing here reproduces it, so "enumeration would have caught
  it at nine elements" remains the note's claim, not this one's.
- The `Deque` wrapped-layout gap is demonstrated as **unreachable**, not as **hiding a bug**.
  Whether `Deque`'s wrapped-buffer arithmetic has a defect is unknown; the honest statement is
  that the kit could not currently tell.
- ~~The vacuity claim in §"what the kit can say" is reasoned~~ — **now built and measured.**
  `requiringApplicableCases` consults `SpaceCoverage.isComplete` and reports the two causes
  differently; a truncated walk is treated as sampled, since the cases it skipped are the
  ones that would have decided the question. The asymmetry the note predicted held:
  `incomparabilityTransitivity` stays unguarded even where the evidence is conclusive,
  because the fact a guard would establish there is the definition of a total order.
- Slice 1 ships no per-protocol entry point. The algebraic application it was built for is
  demonstrated in tests (`associativityOverEveryTripleOfASmallCarrier`) by passing the law
  to `checkEveryCase` by hand; wiring it into `checkSemigroupPropertyLaws` and its siblings
  is Slice 2.
- Slice 4's budget interaction is reasoned about, not measured.

## What the first draft got wrong

Recorded rather than deleted, because the pattern is the one this repo's notes keep finding —
a justification that looks like reasoning and is actually deference.

| claimed | actually |
|---|---|
| the bridge should ship first, being cheapest and most of the value | its one real cost is an artifact of the `Generator` seam. Own the input source and the cost is gone. Slice order inverted. |
| `overEvery:` overloads are not recommended, since Slice C covers Apple's usage | it covers *Apple's* usage. Exhaustive triples over a small algebraic carrier is the kit's highest-value case and needs a per-protocol entry. |
| row-major ordering, because it "matches what Apple's nesting produces naturally" | worthless as a justification once fidelity is not a goal, and it overstated diagonal's cost. Both are proxies for summed size. |
| the four combinators to build are Apple's four | `everyPermutation` earns nothing here; every triple, every equivalence-class pair, and every action sequence are worth more and have no ancestor. |
| `withSome(maxSamples:)` is a needed fallback | it is a weaker duplicate of a `Generator`. Dropped. |
| diagonal ordering was load-bearing (first spike) | the spike's control was built so both orderings returned the same cell, and demonstrated nothing. Caught and redone; the second spike discriminates. |
| index-shrinking on a bridged space works for free (first spike) | the spike supplied its own value-level shrinker, so it proved the kit's shrinker works, not the claim. That mis-scoped test is what surfaced the `LawCheck.shrink` finding. |
