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
```
