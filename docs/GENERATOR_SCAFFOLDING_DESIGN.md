# Design sketch: Generator scaffolding (partial derivation → suggestion)

_Date: 2026-06-27 · Builds on `GENERATOR_DERIVATION_SCOPE.md` · realizes its deferred Phase 2 (`GeneratorPlan`) + Phase 5 (SwiftInfer refinement seam)_

## The idea in one line

Stop treating "can't fully derive a generator" as a binary `.todo`. When a
type is *partially* derivable, emit a **scaffold `gen()`** — the slots we can
derive filled in, the ones we can't left as editor placeholders — as a
reviewable suggestion. Mirrors SwiftInferProperties: a proposal for the human,
not an all-or-nothing wall.

## Outcome becomes a gradient (three tiers, not two)

| Tier | When | Output |
|---|---|---|
| **Derive** | every slot resolves | complete generator → auto-runs in `PropertyLawTests.generated.swift` (today's behavior) |
| **Scaffold** | our own type, *some* slots resolve | partial `gen()` suggestion: resolved slots filled, unresolved → `<#Generator<T>#>` placeholders |
| **Manual** | external/opaque type (no `TypeShape`) | "write `gen()` against its public API" — can't scaffold the body (unknown public init; the access-control limit) |

Scaffold is the new middle tier. On SwiftLintRuleStudio it targets exactly the
**57 "unsupported member type"** bucket (own structs with one custom field) and
the partial slices of the user-init / enum buckets — types that produce *zero*
value today.

## Keystone data model: `GeneratorPlan` (with holes)

Replace the opaque emitted **string** with a structured tree (the Phase 2 item
from the derivation scope — scaffolding is what finally justifies it). The new
node is `.hole`.

```swift
public indirect enum GeneratorPlan: Sendable, Equatable {
    case leaf(expression: String, imports: Set<String>)   // resolved primitive / known / Type.gen() ref
    case optional(GeneratorPlan)
    case array(GeneratorPlan)
    case set(GeneratorPlan)
    case dictionary(key: GeneratorPlan, value: GeneratorPlan)
    case product(constructor: String, fields: [Field])    // memberwise / user-init / enum case payload
    case sum(cases: [GeneratorPlan])                       // enum → Gen.oneOf
    case always(constructor: String)                       // payload-free case / no-arg
    case hole(typeName: String, reason: String)            // NOT derivable — placeholder slot
}

public struct Field: Sendable, Equatable {
    public let label: String?      // call label, nil for unlabeled
    public let plan: GeneratorPlan
}
```

Derived properties:
- `render(mode:) -> String` — emit Swift source; `.hole` → `<#Generator<typeName>#>`.
- `requiredImports: Set<String>` — union over the tree.
- `isComplete: Bool` — no `.hole` anywhere → eligible for Tier "Derive".
- `holes: [(typeName: String, reason: String)]` — for the suggestion summary.

The existing string emitters (`MemberwiseEmitter`, `EnumCaseEmitter`,
`GeneratorExpressionEmitter`) become thin `render()` wrappers over plans. All
current output stays byte-identical for hole-free plans (locked by existing
tests).

## PropertyLawCore change: stop discarding partial results

Today `memberwiseStrategy` / `initializerBasedStrategy` / `enumCasesStrategy`
return `nil` the moment one slot fails. The change: **always build a plan**,
substituting `.hole` for an unresolvable slot instead of bailing.

```
for each member/param/associated-value:
    if let composed = resolve slot → .leaf(...)
    else                          → .hole(typeName, reason)
```

Then the *caller* decides by tier:
- `plan.isComplete` → today's strategies (`.memberwiseArbitrary` etc.) — unchanged path, auto-test file.
- not complete but a `product`/`sum` exists → **scaffold candidate** (we know the constructor).
- no plan at all (external type, never scanned) → **manual**.

This is additive: the complete path is exactly today's behavior; the partial
path is new information we currently throw away.

## Two emission modes (this matters)

| Mode | Nested own-type (`customer: Customer`) | Unresolvable leaf (`url: URL`) | Goes where |
|---|---|---|---|
| **Inline** (today, Tier "Derive") | inline Customer's full generator | n/a (would be `.todo`) | auto-test file — must compile & be self-contained |
| **Scaffold** (new) | reference `Customer.gen()` | `<#Generator<URL>#>` placeholder | separate suggestion file |

Scaffold mode references `Customer.gen()` rather than inlining, so each type
gets one reviewable generator the user completes once — no duplication, no deep
inlined partials. (`Customer` gets its *own* scaffold suggestion.)

## Hard constraint: scaffolds don't compile → separate output

A `<# #>` placeholder is a compile error. The discovery plugin's
`Tests/<T>Tests/PropertyLawTests.generated.swift` **must always compile**, so
scaffolds **cannot** go there. They go to a **separate, opt-in suggestions
output** — exactly like SwiftInferProperties' RefactorBridge writes proposal
stubs to `Tests/Generated/SwiftInferRefactors/<Type>/…` for review.

This is the architectural tell: **scaffolding belongs in SwiftInferProperties,
not the laws plugin.** SwiftInfer is already the suggestion-for-human-review
tool, and already infers generators from richer signals than structure.

## The loop: PropertyLawCore holes → SwiftInfer fills → suggestion

```
PropertyLawCore                          SwiftInferProperties
───────────────                          ────────────────────
strategy(for:resolve:) → GeneratorPlan   consumes the plan, then:
  (resolved leaves + holes)              1. REFINE resolved leaves with domain hints
                                            Gen<Int>.int()  →  Gen.int(in: 1...10)
                                            (PreconditionInferrer / DomainInferrer)
                                         2. FILL holes when it has evidence
                                            <#Generator<URL>#>  →  mock-synthesized
                                            gen from test fixtures (when present)
                                         3. RENDER remaining holes as placeholders
                                         4. EMIT scaffold `gen()` as a suggestion
                                            (RefactorBridge-style writeout)
```

SwiftInfer already has the pieces: `DerivationStrategist` consumption,
`PreconditionInferrer` (literal-range bounds), `DomainInferrer` (consumer/
producer chains), mock-synthesis from tests, and the RefactorBridge writeout
channel. The new work there is: accept a `GeneratorPlan`, walk it applying
refine/fill, and render the scaffold. This is the same structural-derivation +
semantic-inference composition the ecosystem already does for *property*
suggestions, now applied to *generators*.

## Worked example

`struct Doc: Equatable { let id: Int; let tags: [String]; let url: URL }`,
where the project has tests that build `URL(string: "https://…/\(slug)")`.

1. **PropertyLawCore** → plan:
   `product("Doc", [id: leaf(Gen<Int>.int()), tags: leaf(...array...), url: hole("URL", "no recognized generator")])`.
   `isComplete == false`, constructor known → scaffold candidate.
2. **SwiftInfer refine**: tests show `id` in `1...999` → `id` leaf becomes
   `Gen.int(in: 1...999)`.
3. **SwiftInfer fill**: mock-synthesis sees the URL-construction pattern →
   fills the `url` hole with `Gen…map { URL(string: "https://…/\($0)")! }`.
4. **Emit** (suggestion file):

```swift
extension Doc {
    // Suggested by swift-infer — review and complete. Auto-derived where possible.
    static func gen() -> Generator<Doc, some SendableSequenceType> {
        zip(
            Gen.int(in: 1...999),                                    // id (inferred bound)
            Gen<Character>.letterOrNumber.string(of: 0...8).array(of: 0...8),  // tags
            Gen<Character>.letterOrNumber.string(of: 1...12).map { URL(string: "https://example.com/\($0)")! }  // url (inferred from tests)
        ).map { Doc(id: $0.0, tags: $0.1, url: $0.2) }
    }
}
```

If there were no URL evidence, the `url` line would instead be
`<#Generator<URL>#>  // url — provide a generator` and everything else still
filled. Either way the developer gets ≫0% of the way.

## Sweet spot and limit (be honest about both)

- **Helps:** your own *partially*-derivable structs/enums — the 57 "unsupported
  member" bucket, partial user-init/enum cases. Real, common (one `Color`/`URL`/
  custom field in an otherwise plain struct).
- **Doesn't help:** external/opaque types (200 "no stored properties"). No
  `TypeShape`, unknown public init → no constructor to scaffold. Output stays
  "write `gen()` manually." Scaffolding inserts a tier; it doesn't remove the
  manual one.

## Phasing

| Phase | Deliverable | Home |
|---|---|---|
| **1** | `GeneratorPlan` + `render()`; existing emitters become wrappers (no behavior change; all current tests stay green) | PropertyLawCore |
| **2** | Strategies build partial plans (holes instead of bailing); expose a `partialPlan(for:resolve:)` alongside `strategy(for:)` | PropertyLawCore |
| **3** | Scaffold render mode (sibling `Type.gen()` refs + `<# #>` holes) | PropertyLawCore |
| **4** | SwiftInfer consumes the plan: refine leaves + fill holes + emit scaffold suggestion to a `Generated/` file | SwiftInferProperties |
| **5** | `swift-infer` CLI surfacing ("N scaffoldable types; M complete") + the scoreboard's three-tier split | SwiftInferProperties / discovery |

Phase 1 is a pure refactor (the long-deferred `GeneratorPlan`); Phases 2–3 are
the partial-derivation engine; Phases 4–5 are the SwiftInfer suggestion layer.
Each phase is independently testable and shippable.

## Open questions

1. **Nested partials:** reference `Customer.gen()` always (simpler, per-type
   review) vs. inline a partial Customer plan. Recommendation: reference — each
   type owns its generator.
2. **Refinement contract:** does SwiftInfer mutate the plan tree (replace
   leaf/hole nodes) or emit a parallel "overrides" map keyed by slot path?
   Tree-mutation is cleaner but couples SwiftInfer to the plan shape.
3. **Where the scaffold file lands:** `Tests/Generated/…` (reviewable, manual
   move) vs. `--apply` into `Sources/`. Default to reviewable, mirroring the
   RefactorBridge.
4. **TypeShape bump:** the plan-returning API is an additive PropertyLawCore
   surface SwiftInfer consumes — coordinate the version bump (same as prior
   tiers).
5. **Placeholder fidelity:** `<#Generator<URL>#>` vs. a richer hint comment
   naming the slot + reason. Recommendation: both (placeholder + trailing
   comment).
