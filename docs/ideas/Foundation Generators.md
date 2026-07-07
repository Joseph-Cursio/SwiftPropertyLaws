# Foundation Generators (kit roadmap)

**Status:** ✅ **Shipped** (v3.10.0). All four generators built in `Sources/PropertyLawKit/Public/FoundationGenerators.swift`, 10 tests in `Tests/PropertyLawKitTests/FoundationGeneratorsTests.swift`. Non-breaking additive minor. Implementation notes below record what shipped; the "why low priority" rationale is retained as history.
**Origin:** Extracted from SwiftInferProperties' `docs/ideas/ValueSemantic Kit Proposal.md` §5 (workstream 3), which correctly identified these as a *kit* concern, not an engine one. This is their natural home; the downstream proposal now carries only a one-line pointer here.

## What

Foundation-typed `Gen<T>` convenience generators, so kit users writing hand-authored property tests over Foundation types don't have to roll their own:

| Generator | Type |
|---|---|
| `Gen.date()` | `Date` |
| `Gen.url()` | `URL` (valid URLs only) |
| `Gen.data(of: countRange)` | `Data` (size-controlled) |
| `Gen.uuid()` | `UUID` |

## Where

`PropertyLawKit/Public/`, alongside the existing `NumericGenerators.swift` (`doubleWithNaN` / `floatWithNaN` / `boundedForArithmetic`). The main line **already imports Foundation** (5 files), so these carry no new dependency and no swift-numerics footprint (Foundation ≠ numerics). A sibling `FoundationGenerators.swift` keeps them grouped. They do NOT belong in `PropertyLawComplex` (that's the opt-in swift-numerics line) — Foundation is free on the main line.

## Why low priority (no downstream pull)

The primary downstream consumer, **SwiftInferProperties, does not consume kit generators for its verify path** — it emits its own deterministic curated literals (`ViewModelArgumentGenerator`), precisely because verify needs fixed, reproducible values. So these generators deliver **zero engine capability**; their value is purely convenience for kit users writing PBT *by hand* over Foundation-typed properties. Ship on demand if that demand surfaces — there is no engine-side reason to prioritize them.

## Design notes

- Follow the existing convention: `public static func name() -> Generator<T, some SendableSequenceType>`, per `doubleWithNaN()`.
- `url()` must yield only **valid** URLs — constrain scheme / host / path components; don't fuzz arbitrary strings through `URL(string:)` (most fail to parse).
- `data(of:)` takes a count range for size control (mirrors the proposal's `Gen.data(of: countRange)`).
- Determinism: prefer a fully seeded form over the finite-path non-seeded convention `doubleWithNaN` uses, so failures shrink reproducibly.
- These are independent — ship any subset; no ordering dependency.

## As shipped (v3.10.0)

- **All four fully seeded**, per the determinism design note — every sampled value is a deterministic function of the backend RNG, so failures shrink reproducibly.
- `date()` wraps `swift-property-based`'s seeded `Gen<Date>.date(inYear: 1970 ... 2100)`. The year window is fixed rather than wall-clock-relative, so the sampled stream is stable across runs/machines (only the backend's shrink *direction* is clock-relative, which doesn't change which values are produced).
- `uuid()` draws 16 seeded bytes and stamps the RFC 4122 **version-4** nibble + variant bits, so every value is a well-formed v4 UUID.
- `data(of: ClosedRange<Int> = 0 ... 256)` — seeded byte count in the range, each byte seeded over `0 ... 255`.
- `url()` composes curated scheme / host / path components indexed by three seeded `Gen<Int>.int(in:)` draws (never fuzzes arbitrary strings through `URL(string:)`), guaranteeing valid URLs. A single provably-safe constant fallback covers the (unreachable) parse-failure branch.

## Not in scope here

`frequency` / `recursive` / `sized` / edge-case-biased already exist in the kit / swift-property-based; only the Foundation set above is missing. The proposal's shrinking workstream (WS2) is moot — `.shrink(towards:)` already exists in `swift-property-based` (external) and is used downstream.
