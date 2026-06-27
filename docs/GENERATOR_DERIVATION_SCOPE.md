# Scope: Strengthening Generator Derivation (PropertyLawCore)

_Date: 2026-06-27 · Implements Idea #3 from `~/xcode_projects/PBT_ECOSYSTEM_REVIEW.md` · the shared bottleneck that gates the Idea #2 pipeline's yield_

## Goal

Reduce how often `DerivationStrategist` returns `.todo` (the compile-error placeholder),
so more types get an auto-derived `gen()` and more property-law tests actually run. This
pays off **three times** at once: SwiftPropertyLaws' `@PropertyLawSuite` / discovery plugin,
SwiftInferProperties' M3 generator selection, and (transitively) SwiftIdempotencyPropertyBased.

## The crux finding

The underlying engine (`swift-property-based`, module `PropertyBased`) **already ships the
combinators** needed for far more than is derived today:

| Capability | Engine support (verified) | Currently derived by PropertyLawCore? |
|---|---|---|
| Bounded numerics | `Gen<Int>.int(in:)`, `.value(in:)`, floats | ❌ emits unbounded `Gen<Int>.int()` |
| Optionals `T?` | `.optional`, `.optional(valueRate:)` | ❌ `.todo` |
| Arrays `[T]` | `.array(of: ClosedRange<Int>)` | ❌ `.todo` |
| Dictionaries / Sets | `.dictionary(ofAtMost:)`, `.set(ofAtMost:)` | ❌ `.todo` |
| Sum types / enums w/ payloads | `Gen.oneOf(...)`, `Gen.frequency(...)` | ❌ only payload-free `CaseIterable` |
| Product types ≤10 fields | `zip2…zip10` + `.map` | ✅ `memberwiseArbitrary` |
| Constants | `Gen.always(_)` | ✅ (via raw types only) |

So the gap is **not** the engine — it's that `DerivationStrategist.strategy(for:)` exact-string
matches each member's `typeName` against a 14-case `RawType` enum
(`Sources/PropertyLawCore/DerivationStrategy.swift:54`), so `"Int?"`, `"[Int]"`, `"Money"`
all miss and fall to `.todo`. The member type is carried as a **verbatim source string**
(`MemberBlockInspector.swift:32`, `typeAnnotation.type.trimmedDescription`) and never parsed.

## Current state (verified)

`strategy(for: TypeShape)` priority (`DerivationStrategy.swift:178`):
`userGen → caseIterable(payload-free) → memberwiseArbitrary(struct, all-stdlib-raw, ≤10, no user init) → rawRepresentable(enum) → todo`.

Falls to `.todo` on: optionals, arrays, dicts, sets, **nested custom types**, enums with
associated values, structs with a user `init`, arity > 10, and any non-`RawType` member.
`TypeShape` keeps only `hasUserInit: Bool` (not the init signature) and member type **strings**
(`DerivationStrategy.swift:120`) — so the information needed for the harder cases is currently
discarded at extraction time.

**Division of labor already exists** and should be preserved: SwiftInferProperties does
*semantic/domain* inference from bodies & tests (`PreconditionInferrer` → `Gen.int(in: 1...10)`,
`positiveInt`, `stringLength`; `DomainInferrer` → consumer-producer `Gen.map(forward)`), while
PropertyLawCore does *structural* derivation from type shape. This scope strengthens the
**structural** half and defines a cleaner seam so domain hints refine structural leaves.

## Architectural shift: derivation must compose over a type universe

Today `strategy(for: TypeShape) -> DerivationStrategy` is a **pure function of one type in
isolation**. Nested custom types can't work that way — deriving `struct Order { let customer: Customer }`
requires knowing whether `Customer` is itself derivable. Two options:

- **(a) Resolver closure:** `strategy(for: TypeShape, resolve: (String) -> DerivationStrategy?)`
  — the strategist recurses into member types via `resolve`. Minimal surface change.
- **(b) Whole-module graph:** build all `TypeShape`s, then resolve to a fixpoint with cycle
  detection (bounded depth → `.todo` on unbounded recursion).

Recommendation: **(a)** for the first pass (smaller change, the discovery tool already has all
module types in hand to back the closure), with (b)'s cycle handling folded in as a visited-set.
This mirrors `SwiftEffectInference.EffectSymbolTable`'s multi-hop fixpoint — same shape of
problem, a known-good precedent in the ecosystem.

**Interchange representation.** Replace the opaque emitted *string* with a structured
`GeneratorPlan` tree (leaf = primitive/raw/known-type gen; node = `.optional(of:)`,
`.array(of:)`, `.product(init:, fields:)`, `.sum(cases:)`, `.userGen`, `.todo`). Source
emission becomes a final `render(GeneratorPlan) -> String` step. This is what lets
SwiftInferProperties' domain hints **refine a specific leaf** (e.g. swap the `count: Int` leaf
for `Gen.int(in: 1...10)`) instead of regex-patching a string — directly enabling the clean
composition Idea #2 wants. Composed plans also **shrink for free** (engine's `Shrink.*` types
thread through `zip`/`map`/`optional`/`array`), unlike `.todo`/`Gen.always`.

## Tiered improvements

### Tier 1 — parse the member type string (highest leverage / effort) ⭐
Parse `typeName` structurally instead of exact-matching, and recurse on the element type:
- `T?` → `<plan(T)>.optional`
- `[T]` → `<plan(T)>.array(of: 0...8)`
- `[K: V]` → `zip(<plan(K)>, <plan(V)>).dictionary(ofAtMost: 0...8)`
- `Set<T>` → `<plan(T)>.set(ofAtMost: 0...8)`

Pure plumbing over existing engine combinators; no engine change; removes a large fraction of
`.todo`s on real models. **Effort: M.**

### Tier 2 — known stdlib/Foundation value types
Extend the leaf table beyond the 14 numerics to common members that currently `.todo`:
`Character`, `URL`, `Date`, `UUID`, `Data`, `Decimal`. Each maps to a curated recipe, e.g.
`Date ← Gen<Double>.double(in: …).map { Date(timeIntervalSince1970: $0) }`. Flag which need a
genuinely new engine generator vs. a `.map`-composed recipe (e.g. a shrinkable `UUID` gen from
random bytes is worth upstreaming to `swift-property-based`; `Gen.always(UUID())` is
nondeterministic and unfit for PBT — do **not** use it). **Effort: S–M.**

### Tier 3 — nested custom types (the architectural payoff)
With the resolver closure (above), a struct/enum member whose type is another derivable user
type composes its plan. Visited-set guards recursive types (→ bounded depth → `.todo`).
Unblocks real domain aggregates. **Effort: L** (depends on the resolver + `GeneratorPlan`).

### Tier 4 — enums with associated values
Derive each case's payload plan (recursively), combine with `Gen.oneOf(...)` / `Gen.frequency(...)`
(engine supports both). Requires capturing enum cases + their associated-value types in
`TypeShape` (currently discarded). **Effort: M–L.**

### Tier 5 — arity > 10
`zip` caps at 10. For ≥11 stored members, chunk into groups of ≤10, `zip` each chunk, then
`zip` the chunk-tuples and `.map` through the init. Mechanical once the emitter is plan-based.
**Effort: M.**

### Tier 6 — structs with a user `init`
A user `init` suppresses the synthesized memberwise init, forcing `.todo` today
(`DerivationStrategy.swift:210`). If the init's parameter list is captured (it isn't —
`TypeShape` keeps only `hasUserInit: Bool`), derivation can target that init when its params
map to derivable types. **Effort: M**, gated on TypeShape enrichment. Lower priority.

### Step 0 (prerequisite) — enrich `TypeShape` + extraction
Tiers 3/4/6 need information currently dropped at `MemberBlockInspector`:
- parsed member types (not raw strings) — or parse downstream in the strategist,
- enum cases + associated-value types,
- user-init parameter signatures.

This changes PropertyLawCore's **public** model (`TypeShape`, consumed by SwiftInferProperties
via `.toKitShape()` in `StrategistDispatchEmitter.swift:168`). Treat as an additive,
versioned change; coordinate the bump with SwiftInferProperties.

## Out of scope (name them so they're not silently assumed)
- **Dependent generation** (a field whose domain depends on another field's *value*). The
  engine has no public `flatMap`; `.array(of:)` covers size-dependent collections but not
  value-dependent fields. This is semantic, belongs to SwiftInfer, and is hard even there.
- **Generic types with constraints** (`OrderedSet<T>`) beyond a curated table — SwiftInfer
  already curates a few via `curatedOCRecipe`; keep that pattern.
- **Domain/bounds inference** — stays in SwiftInferProperties (`PreconditionInferrer`); this
  scope just exposes leaves it can refine.

## Validation metric
The discovery tool already prints "types needing manual gen()" with `.todo` counts
(`PropertyLawDiscoveryTool.swift:109`). Use it as the scoreboard: run the strengthened
strategist against the validation corpus (swift-argument-parser, swift-collections, Hummingbird)
and track `.todo` reduction per tier. **Synergy:** more derivable types → more law checks
actually execute → directly advances SwiftPropertyLaws' still-unmet PRD gate ("catch a real
semantic bug in 5+ packages"), which is currently blocked partly because scan-only passes never
ran law checks.

## Phasing
| Phase | Deliverable | Effort |
|---|---|---|
| **1** | Tier 1 (type-string parsing: optional/array/dict/set) + `.todo` scoreboard on corpus | M |
| **2** | `GeneratorPlan` interchange + plan-based emitter (refactor; no behavior change) | M |
| **3** | Tier 2 (known value types) + Tier 5 (arity >10) | S–M each |
| **4** | Step 0 TypeShape enrichment, then Tier 3 (nested) + Tier 4 (enum payloads) | L |
| **5** | Domain-hint refinement seam wired to SwiftInferProperties (ties to Idea #2) | M |

Order rationale: Tier 1 is pure yield with no model change; the `GeneratorPlan` refactor (Phase
2) is the enabler for everything structural *and* for SwiftInfer refinement, so it precedes the
deeper tiers.

## Open decisions
1. **Resolver closure vs. whole-module graph** for nested types. Recommendation: closure first,
   visited-set for cycles; graph later only if needed.
2. **`GeneratorPlan` now or later.** Recommendation: Phase 2, before Tiers 3–6 — emitting more
   strings first would mean rewriting them. Doing Tier 1 as strings first is acceptable (small).
3. **Default collection size range** (`0...8`?) and numeric default bounds — pick conservative,
   shrink-friendly defaults; make overridable.
4. **Where shrinkable `Date`/`UUID`/`Data` gens live** — curated in PropertyLawCore vs.
   upstreamed to `swift-property-based`. Recommendation: upstream the genuinely reusable ones.
5. **TypeShape model bump coordination** with SwiftInferProperties (additive; needs a release).

---

## Measured yield (2026-06-27) — reshapes the roadmap

After shipping Tier 1 (composite members) + Tier 2 (Character/Date), I ran
`PropertyLawDiscoveryTool` against three corpora and diffed HEAD vs the
pre-Tier-1 commit. **Tiers 1–2 unlocked almost nothing on real code:**

| Corpus | Types | manual `gen()` before | after | unlocked |
|---|---|---|---|---|
| Sitrep (real app) | 19 | 19 | 19 | 0 |
| swift-property-based | 24 | 22 | 22 | 0 |
| swift-syntax | 1009 | 998 | 997 | 1 |

`.todo` reasons, aggregated (new tool scoreboard):

| Reason | Count | Share |
|---|---|---|
| **user-defined init** | 669 | **64%** |
| no visible stored properties | 183 | 18% |
| enum without CaseIterable/raw | 77 | 7% |
| unsupported member type (nested/custom) | 64 | 6% |
| non-struct (class/actor/enum-payload) | 45 | 4% |

**Findings that overturn the original phasing:**
- Composite/value-type members (Tiers 1–2) were *not even a bucket* — that
  gap barely exists in real code. The work is correct but low-yield.
- **`user-defined init` (Tier 6) is the dominant addressable gap**, not
  nested types. It was ranked *low* in the original phasing — it should be
  **first**. Derivation must capture the init's parameter signature and
  build through it (needs Step 0 TypeShape enrichment).
- `no visible stored properties` (18%) is largely **non-addressable noise**:
  extensions adding conformances to *external* types (`Array`, `String`,
  `ClassDeclSyntax`, …) whose stored members the tool can't see, plus
  namespace enums. The scoreboard should exclude these so future
  measurement is honest.
- **Nested custom types (Tier 3) is only ~6%** and is *gated on* user-init
  support — most custom member types themselves have custom inits, so Tier 3
  doesn't pay off until Tier 6 lands.

**Revised priority:** (1) Tier 6 user-init derivation; (2) separate
addressable vs non-addressable in the scoreboard; (3) Tier 4 enum payloads
(~7%); (4) Tier 3 nested (~6%, gated on 1); (5) non-struct/classes (~4%).

**Caveat:** three corpora, and swift-syntax (compiler-generated wrappers)
dominates the user-init count; the real-app corpora are small. Broaden the
corpus (a few real SwiftUI/server apps) to firm up the ranking. But the
"composite-member gap is tiny / structural reasons dominate" signal is
consistent across all three.

### Tier 6 shipped — and the tiers interlock

After building Tier 6 (initializer-based derivation), re-measured vs. the
Tier-1/2 HEAD:

| Corpus | before | after | unlocked |
|---|---|---|---|
| Sitrep | 19 | 18 | +1 |
| swift-property-based | 22 | 22 | 0 |
| swift-syntax | 997 | 980 | +17 |

The `user-defined init` bucket on swift-syntax only fell 664 → 647. **Most
user-init types also have custom-type init parameters** (or failable/throwing
inits), so they stay `.todo` — now reported with the init-specific reason.
The lesson: **the tiers are not independent.** Tier 6 is a *prerequisite*
that compounds with **Tier 3 (nested custom types)** — a struct with
`init(child: Customer)` needs both the init lift *and* a generator for
`Customer` (which itself usually needs Tier 6). Neither tier alone unlocks
these; together they should cascade.

**Revised next step:** Tier 3 (nested custom types) via a whole-module
resolver that recurses into member/parameter types using the same
`DerivationStrategist` — now justified by the data, and multiplicative with
the Tier 6 work already in place. Also worth doing: exclude non-addressable
types (extensions on external types, namespace enums) from the scoreboard so
the addressable-yield denominator is honest.

### Tier 3 shipped — diminishing returns, and the corpus is the limit

`GeneratorResolver` (whole-module, memoized, cycle-guarded) now inlines
nested struct / CaseIterable-enum generators and references `Type.gen()` for
user-gen types. Re-measured vs. the Tier-6 HEAD:

| Corpus | before | after | unlocked |
|---|---|---|---|
| Sitrep | 18 | 18 | 0 |
| swift-property-based | 22 | 22 | 0 |
| swift-syntax | 980 | 977 | +3 |

Marginal — because the *nested* types in these corpora are themselves mostly
non-derivable: classes, enums-with-payloads (Tier 4), external types, or
**nested type *declarations*** (`Report.Scan`) whose qualified spelling the
simple-name universe doesn't match. Tier 3 works (proven by tests + the clean
`Order`→`Customer` scan case), but the corpora gate it.

**The real conclusion from four tiers of measurement:** generator derivation
is now solid for the *plain value-type* world (raw, composite, Character/Date,
user-init, nested value types), but these three corpora aren't value-type
heavy — Sitrep is a CLI tool (classes/visitors), swift-syntax is node wrappers,
swift-property-based is closures/generators. **The bottleneck is no longer the
derivation engine; it's corpus fit.** Before building more tiers (Tier 4 enum
payloads, qualified nested-name resolution), measure on a *domain-model-heavy*
target (a SwiftUI/Codable app) to see whether the engine already clears it —
the yield question is now empirical about *which code*, not *which tier*.

**Performance note:** swift-syntax scans in ~20s, dominated by SwiftParser on
258 large files — unchanged by Tier 3 (memo on/off both ~20s). The resolver
itself is negligible.

### Corpus-fit confirmed: SwiftLintRuleStudio (478 types)

Measured a value-type-heavier real app (SwiftLintRuleStudio, 368 files) — the
"better corpus" the previous conclusion called for. Baseline (pre-Tier-1) vs.
HEAD (Tiers 1/2/3/6):

| | manual `gen()` | derivable | rate |
|---|---|---|---|
| baseline `298c5e3` | 459 | 19 | 4.0% |
| HEAD (4 tiers) | 436 | **42** | 8.8% |

**The four tiers more than doubled derivable types (19 → 42, +121%)** — vs.
~+1 on the non-value-type corpora. This is the validating data point: the
derivation work pays off in proportion to how value-type-heavy the target is.

Remaining `.todo` buckets on SLRS:

| Reason | Count | Addressable? |
|---|---|---|
| no visible stored properties | 200 | mostly **no** — dominated by SwiftUI `View` structs (52+ files; computed `body` + type-inferred `@State`), plus extension-only external types (~6, e.g. `UserDefaults`) and empty/all-computed structs. (Not namespace enums — those land in the enum bucket.) |
| enum without CaseIterable/raw | 61 | **yes — Tier 4 (enum payloads)** |
| non-struct (class/actor) | 61 | mostly no (reference semantics, out of scope) |
| unsupported member type | 57 | partly (gated on Tier 4 / class support) |
| user-defined init | 56 | partly (Tier 6 already takes the derivable ones) |
| arity > 10 | 1 | yes (Tier 5, trivial) |

**The largest addressable remaining bucket is `enum without CaseIterable/raw`
(61) — i.e. Tier 4 (enum payloads via `Gen.oneOf`).** That's the data-justified
next tier if continuing. The 200 "no stored properties" should be excluded
from the scoreboard denominator (non-addressable) for an honest rate.

### Tier 4 shipped — enum payloads

`enumCases` strategy: each case → `Gen.always(T.c)` (plain) or
`zip(...).map { T.c(...) }` (payload), combined with `Gen.oneOf(...eraseToAny())`.
Associated values resolve through the Tiers 1–3 machinery (composites, Date,
nested customs), so it composes with everything prior. Slots in after
CaseIterable/raw so those enums are untouched. Re-measured on SLRS:

| | derivable | enum bucket |
|---|---|---|
| pre-Tier-4 | 42 | 61 |
| post-Tier-4 | **64** | 41 |

**+22 derivable (+52%).** 20 enums derived directly; the remaining 41 in the
bucket have non-derivable associated values (custom non-derivable types,
closures, external types). Across all tiers the corpus arc is now
**19 → 64 derivable (3.4×)**.

**State of the engine after four shipped tiers (1/2/3/4/6):** derivation now
covers the plain value-type world end to end — raw, composite, known value
types, user-init structs, nested value types, and enums (plain + payload).
The remaining `.todo` on SLRS is dominated by genuinely out-of-scope or
non-addressable shapes: classes (61, reference semantics), "no stored
properties" (200, mostly SwiftUI views + external-type extensions), and
members/associated-values that bottom out in those. The high-leverage
derivation work is essentially done; further gains are narrow (qualified
nested-type names, arity > 10) or out of scope (classes). The next
*ecosystem* lever is no longer derivation — it's the scoreboard honesty fix
(exclude non-addressable types) and moving up to Ideas #1/#2.
```
