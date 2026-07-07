# Foundation Generators (kit roadmap)

**Status:** Proposed, unbuilt — **low priority.** Non-breaking (a `PropertyLawKit` minor, e.g. v3.10.0).
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

## Not in scope here

`frequency` / `recursive` / `sized` / edge-case-biased already exist in the kit / swift-property-based; only the Foundation set above is missing. The proposal's shrinking workstream (WS2) is moot — `.shrink(towards:)` already exists in `swift-property-based` (external) and is used downstream.
