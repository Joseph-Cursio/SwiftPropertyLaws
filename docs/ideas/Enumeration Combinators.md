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
it: `.thorough` draws ten thousand contiguous deques.

The weaker general version also has a number. Over a 1 024-case space (subsets of `0..<10`),
a `.standard` 1 000-trial run covered **636 cases, 62%** — 388 unreached, and none of them
reported as unreached. Enumeration's contribution there is the denominator, not the
coverage.

## When to reach for a space — and when not to

**Rewritten after measurement, and the first version was wrong in a way worth keeping on
record.** It listed four conditions in a confident order and three reasons not to, all
reasoned from the machinery rather than from evidence, because at the time there was none.
Two of the three objections turned out to be artifacts of a half-built implementation, and
the ranking of the four conditions was backwards. The corrections are in §"What the first
draft got wrong"; this section is what the measurements actually support.

The organising test still holds, and did not originate here — it came from someone reading
this note and summarising it back:

> Enumeration pays where the interesting configurations are **defined** rather than
> **constructed**.

What measurement added is that *defined rather than constructed* splits into two very
different payoffs, and only one of them is about catching bugs.

### The dividing line: is the law conditional?

**Measured twice, and the two results point opposite ways.**

**An unconditional law over a reachable state — sampling misses nothing.** A reducer whose
`withdraw` skips its balance check while frozen, over four actions: sampling at the default
`0...16` length found it on **50 of 50 seeds**. What it *reported* was a median of **13
moves**; the walk reported `[freeze, withdraw]`, the two that prove it. The payoff is
minimality — roughly a 6.5× reduction in what a reader has to decode — and nothing at all in
detection.

**A conditional law whose antecedent is rare — sampling misses the bug entirely.**
`Equatable.transitivity` says nothing until three values satisfy `x == y && y == z`. Against
a genuinely non-transitive `==`, at `.standard`, across 20 seeds:

| generator | caught |
|---|---|
| `0...3` — the hand-narrowed one in the planted-bug suite | 20/20 |
| `0...200` — the one anyone would write | **0/20** |

No budget fixes that: at a 100-value domain the chain fired **0 times in 1 000 trials**. The
walk catches it at every carrier width and is *faster* than the sampled run that misses,
because smallest-first reaches the witness long before it would consider eight million
triples.

So the first question is not *is my domain bounded?* but **does this law have an
antecedent?** If it does and the antecedent is rare, a walk is the difference between
testing and not testing. If it does not, a walk buys a better counterexample and a
denominator.

### The four conditions, reordered by what they were worth

1. **The law is conditional and its antecedent is rare.** The only condition measured to
   change *detection*. Ask: *does the property read `!(antecedent) || consequent`, or guard
   and return true?* Then ask how often that antecedent can actually fire. A narrow
   generator hand-tuned until it does is the manual version of this fix — paid for once per
   law, with nothing to say whether it worked.
2. **The configuration is describable but not reachable.** `Deque(array)` produced 1 000
   contiguous buffers and no wrapped one, because the head only moves when you `prepend`.
   Probability zero, not rare. Ask: *can I describe the case without being able to build it
   the generator's way?*
3. **The defect belongs to the subject, not the input.** `LyingCount` misreports its count
   at one length; no input drawn from a single carrier exposes that. Ask: *does varying the
   input, at a fixed subject, explore what I am worried about?* If not, vary the subject.
4. **The law is quantified over a small carrier.** Eight values cubed is 512 triples,
   cheaper than choosing a budget. The weakest of the four: it makes a run tidier without
   making it stronger, unless one of the three above also applies.

### Two reasons not to, down from three

- **The construction path and the space coincide, and the law is unconditional.** A walk
  then buys a denominator and a shorter counterexample. Both are worth something; neither is
  worth restructuring a test for.
- **The domain admits no description worth walking.** `Int`, strings, anything recursive
  without a depth cap. Random draws reach values nobody would have enumerated, which is why
  sampling remains the default for most code.

**The third objection is withdrawn.** It said a walk only surprises you inside a space you
described, while random generation can surprise you *about* the space — and that is very
nearly backwards. This note's own opening argument is that **a generator is bounded by a
description too**: `Gen.int(in: 0...10)` never yields `Int.min`, `Deque(array)` never wraps.
Random draws do not escape a described boundary, they escape an *unexamined* one, and the
space's boundary is the one you can inspect and be knowingly wrong about. What survives is
the second bullet above, which is about size rather than surprise.

**The "large space" objection is gone too**, and was stale when written: `.sampledFromSpace`
draws from a space while keeping the index, so a space too large to walk still shrinks toward
its smallest case and still reports a denominator.

### Expect to find nothing — usually, and now we know when

The `Deque` walk found no defect across 107 layouts, and the action-sequence walk found
nothing sampling had not already found. Those are the normal outcomes and they are not
failures: the first converted *"the kit cannot tell"* into *"correct across every layout"*.

The exception is condition 1. Where a law is conditional and its antecedent is rare, expect a
walk to find something — because the sampled run was very likely not testing the law at all.
That is the one case where a green sampled suite and a green walked suite are not making the
same claim.

## What the kit should enumerate — derived from our laws, not Apple's

Apple's four combinators exist because their subject is `Collection` index arithmetic. Ours
is 39 protocols, and the spaces that pay are different ones. This list is what the menu
should be; only the first two have `StdlibUnittest` ancestors.

**All four now ship, and the two that arrived late are the two that changed the
conclusion.** Slice 1 built triples, ranges and subsets, and stopped — which left the menu
half-built while the design note read as though it were complete. Sequences came later and
measured *minimality*; equivalence-class pairs came last and measured *detection*, which is
the result §"When to reach for a space" is now organised around. The gap between "the note
proposed four" and "the kit shipped three" went unnoticed for the whole of the first arc.

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

## Coverage should be a reported fact — done, and the budget renamed

`TrialBudget.exhaustive(10_000)` named a trial count. The first draft proposed a separate
entry point plus a corrected doc comment; the shipped answer went further, because
`.exhaustive` was this kit's own instance of the defect its notes keep recording — **a
default presented as a guarantee**, in the public API.

Both halves are now done. `CheckResult` carries what the run actually covered — `walked all
512 cases`, `walked 100 of 1024` after a `prefix` — under the same nil-versus-empty
discipline as `nearMisses`. And the tier is now **`.thorough`**, payload-free, with
`exhaustive(_:)` surviving as a deprecated factory so expression call sites still compile.

Payload-free matters: a tier carrying a count *is* `.custom(trials:)` under another name,
which is how the old spelling came to be two ways of saying one thing. Three named effort
tiers plus one escape hatch is the shape that was wanted.

The prose is the evidence the name was wrong. Three files — `SpaceCoverage`,
`DequeLayouts`, `SyntaxGenerators` — carried a paragraph and five references whose only job
was to explain that the identifier did not mean what it said. Those are deleted or restated
positively.

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

**Slice 3 — the `Generator` bridge. SHIPPED, and its concessions since closed for suites
that can take an `InputSource`** — see the sampled-space note at the end of this section.

**Slice 3 — the `Generator` bridge. SHIPPED.** `Enumeration.generator` draws from a space
at random as an ordinary kit `Generator`, which is the door into the forty-odd suites with
no `overEvery:` entry — `Equatable`, `Hashable`, `Collection` and the rest all take a
`Generator`.

**Both concessions are pinned by tests**, because a concession that drifts from the code is
worse than none. The kit's per-law shrinker is value-level and no driver threads a
`Generator`, so the index shrinker in the bridge's own type is not consulted: a failure is
the first drawn, not the smallest that exists. And a sampled run reports `nil` coverage, so
it cannot say what fraction of the space it saw. `theBridgeDoesNotShrink` and
`theBridgeReportsNoCoverageButAWalkDoes` fail if either stops being true.

What survives sampling is the reason to want it: a space's cases are *defined* rather than
constructed, so it reaches configurations a construction-path generator never produces.
That belongs to the space, not the traversal.

**The `Deque` gap this note opens with is now closed.** A layout cannot be drawn, only
built — the head moves only when you `prepend` — so `DequeLayouts.everyLayout()` enumerates
`(capacity, prepended, appended)` arrangements: **107 of them, 59 wrapped**, against the
array path's 0 of 1 000. Contents are fixed at `0 ..< count`, so two arrangements of one
size are equal as values and differ only in head position, which is what makes it a test of
layout rather than of contents. `DequeLawsTests` runs the RandomAccess chain and both
mutation suites over it. They pass — so `Deque`'s wrapped-buffer index arithmetic is
correct, which the kit previously could not have determined either way.

Mutation-tested: 3 mutants in a new `space-sampling` shape, 3 killed.
`layout-space-never-prepends` is the sharpest in the corpus — it builds every arrangement
by appending, so nothing is wrapped, and the space still enumerates, still reports its size,
and still drives every law to a pass while closing nothing.

**The bridge's two concessions, closed where they could be.** `.sampledFromSpace` is a third
`InputSource` case that keeps the index inside the driver: a failure shrinks toward index 0
— the smallest case, since spaces are ordered — and the run counts distinct combinations
drawn against a denominator it knows. Measured against the bridge on the same space and law:
the bridge reports whatever came up at 0 shrink steps; this reports `subset=[0, 1, 2]`, the
minimal witness. Surface is `checkSampledCases` plus a `sampling:` entry beside `overEvery:`
on the six algebraic and three strict-weak-ordering suites.

Coverage counts distinct **combinations**, not draws and not positions. Counting draws
would let 1 000 draws over 64 cases report `casesRun: 1000, spaceSize: 64` and call itself
complete; counting positions would let a ternary law that drew all 32 carrier values claim
complete coverage of 32 768 triples. The denominator is `fullCount ^ arity`, or `nil` when
that overflows. **The second mistake was in the first implementation and was caught while
writing the tests rather than by them**, which is why it is now also a mutant.

**This does not retire the bridge.** The forty-odd suites that take only a `Generator` still
need it; the sampled source is better wherever a law can take an `InputSource`.

**Slice 4 — carrier enumeration around existing suites. SHIPPED.**
`checkEveryCarrier(of:options:perCarrier:suite:)` runs an existing suite once against each
case of a carrier space. Every other entry varies a law's *inputs*; this varies its
*subject*.

**The budget convention this item predicted would be needed is the whole design.** Apple
composes this freely because their checkers are deterministic — one pass per carrier
exhausts it. Ours sample, so the naive composition multiplies: 107 carriers × 1 000 trials
× 15 laws is 1.6 million evaluations from one innocuous-looking call. `perCarrier` is
therefore a separate explicit parameter defaulting to `.sanity`, and `options.budget` is
ignored. The default is a claim rather than caution: in a carrier walk the variety comes
from the carriers, not the trials.

Results merge one per law with `trials` summing the inputs drawn and `coverage` describing
the **carrier** space. The walk stops at the first failing carrier, so the one reported is
the smallest exhibiting the failure.

**What it catches that nothing else does.** `LyingCount` is a `Collection` whose `count` is
correct at every length but seven — a property of the *subject*, not of any input drawn
from it. Pointing the suite at one carrier finds it only if that carrier is the seventh, and
no budget improves those odds, because the budget varies inputs. The control is asserted
too: the same suite passes on every other single carrier.

**It also sharpens Slice 3's `Deque` work.** The generator bridge draws layouts as inputs,
so each law *probably* meets every arrangement — coupon-collector puts it near 578 draws for
107 layouts — and cannot say that it did. The carrier form meets every arrangement by
construction and reports the denominator.

Mutation-tested: 3 mutants in a `carrier-walk` shape, 3 killed. Two are about cost or
honesty rather than correctness — a run that silently multiplies the caller's budget, and a
walk that stopped early while claiming complete coverage — which is the character of this
entry point.

**Not recommended, and still not: `overEvery:` overloads on every protocol suite.** The
48-signature cost lives there, and Slices 2 to 4 between them cover the ground — a walked
entry where the laws are quantified over a carrier, a bridge everywhere else, and a carrier
walk around any suite at all.

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
- Slice 4's budget default (`.sanity` per carrier) is reasoned, not measured. The claim that
  carrier variety beats trial depth is untested — it is the kind of thing a corpus run would
  settle and nothing here settles it.

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
| the four applicability conditions, in the order first written | backwards. Condition 4 (a small carrier) led; condition 1 (a conditional law with a rare antecedent) came third and is the only one measured to change **detection** — sampling missed a non-transitive `==` on 20 of 20 seeds at a realistic domain. |
| "you want to be surprised" is the real limit of the approach | nearly backwards. A generator is bounded by a description too, which is this note's own opening argument. Random escapes an *unexamined* boundary, not a described one. Withdrawn; what survives is that some domains admit no description worth walking. |
| a space too large to walk sends you back to a plain `Generator` | stale when written. `.sampledFromSpace` keeps the index, so a large space still shrinks toward its smallest case and still reports a denominator. |
| "expect to find nothing" as a general expectation | true for unconditional laws, measured twice. False for the one category the note itself named: a conditional law whose antecedent is rare was not being tested at all. |
| diagonal ordering was load-bearing (first spike) | the spike's control was built so both orderings returned the same cell, and demonstrated nothing. Caught and redone; the second spike discriminates. |
| index-shrinking on a bridged space works for free (first spike) | the spike supplied its own value-level shrinker, so it proved the kit's shrinker works, not the claim. That mis-scoped test is what surfaced the `LawCheck.shrink` finding. |
