# Floating-Point Law Oracle — Reconciliation of Book §8.1.4–8.1.7 and the Kit

**Status:** **Applied.** Work A (book prose §8.1.6/§8.1.7) and Work B (kit code)
are both landed. See "Applied — what shipped" below for the as-built record and
the two deviations from the draft design.
**Scope:** the `sameResult` (NaN-reflexive, approximate) oracle for equational
laws over floating-point-backed `Numeric` types (`Double`, `Float`,
`Complex<Double>`), and the corresponding corrections to Chapter 8
§8.1.4–8.1.7.
**Author context:** written after auditing whether the chapter's prose matches
the shipped kit. It does not — and part of the prose is also wrong on its own
terms. This note records what to change in *both*.

---

## 1. The problem

Chapter 8 §8.1.5 describes a `sameResult` oracle —
`(a.isNaN && b.isNaN) || a ≈ b` — used to compare the two sides of an equational
law (commutativity, associativity, distributivity, …) instead of the type's raw
`==`. The kit does **not** implement this. Its algebraic laws
(`NumericLaws.swift`, `AdditiveArithmeticLaws.swift`, `SignedNumericLaws.swift`)
bake `==` directly into each `property:` closure, e.g.
`first * second == second * first`. For `FloatingPoint` the inherited algebraic
chain is therefore **deliberately not auto-run**; for `Complex<Double>` the
validation harness **suppresses** the rounding-fragile laws
(`ComplexLawsTests.swift`, `floatingPointArithmeticSuppressions`).

Before implementing the oracle to close that gap, the prose's logic was audited.
The core is sound; two supporting claims are not.

## 2. Logic audit of §8.1.4–8.1.7

### Sound — §8.1.4, §8.1.5

- **§8.1.4 (NaN-as-oracle trap).** With both sides NaN, `f(a,b) == f(b,a)`
  evaluates `NaN == NaN` → `false`, failing commutativity on a genuinely
  commutative `f`. Real artifact. ✓
- **§8.1.5 (`sameResult`).** `(a.isNaN && b.isNaN) || a ≈ b` fixes it and stays
  self-correcting. Verified: Swift's `min(NaN, 1) == NaN` but `min(1, NaN) == 1`
  (because `min` is `b < a ? b : a` and every `<` involving NaN is false), so a
  genuinely asymmetric `f` still fails because `sameResult(NaN, 1) == false`. ✓

### Flawed — §8.1.6 (the Complex "authority" argument)

The *conclusion* (make the `Double` oracle NaN-reflexive) is fine; the *stated
justification* is not. "`Complex(x,0)` faithfully embeds `Double`'s `x`, so any
law true over ℂ must hold over ℝ" breaks exactly at the point it is invoked:

- The embedding is faithful only for **finite** values. `Complex` collapses **all**
  non-finite values — `inf` *and* `nan` — into a single "point at infinity."
- So `Complex`'s NaN-reflexivity is a **loss of information**, not a truer
  semantics: `Complex(nan,0) == Complex(inf,0)` is `true`, while
  `Double.nan == Double.inf` is `false`.
- Consequently the cross-carrier consistency is **partial**: a NaN-reflexive
  `Double` `sameResult` agrees with `Complex` on `nan`-vs-`nan` but still diverges
  on `inf`-vs-`nan`.

`Complex` is the **lossier** carrier here, not a higher authority. NaN-reflexivity
should be justified by §8.1.5's own argument (it is the correct equivalence for an
equational law), standing alone — not by an appeal to `Complex`.

### Wrong where it counts — §8.1.7 (tolerance "rescues" associativity)

The taxonomy claims rounding failures "differ by a few ULPs" and are "resolved by
the tolerance oracle." True for **well-conditioned** ops; **false** for
associativity/distributivity under **catastrophic cancellation**:

```
a = 1e20, b = -1e20, c = 1
(a + b) + c = 0 + 1          = 1
a + (b + c) = 1e20 + (-1e20) = 0     // b + c rounds to -1e20
```

The two sides differ by `1` — a **full magnitude**, not a few ULPs — and a
property generator *will* find it. Under §8.1.7's own rule ("full magnitude =
genuine = real bug") this gets **misclassified as a bug**, though float
non-associativity is expected, not a defect. No fixed tolerance rescues it,
because the error is unbounded.

The sharp version:

- **`+` and `*` are commutative *exactly* in IEEE-754** (bit-for-bit, modulo NaN).
  Commutativity needs the NaN-reflexive fix and **no tolerance at all**.
- **Associativity, distributivity, subtraction-inverse** round and, under
  cancellation, fail by **unbounded** amounts. They hold to **no** tolerance.

So `sameResult`'s "approximate" component is applied precisely to the laws where
it is either **unnecessary** (commutativity) or **insufficient** (associativity).
That is the logical hole.

## 3. Which float laws are actually runnable

| Law over floats | Holds? | Sound treatment |
|---|---|---|
| commutativity `+`, `*` | exactly, except NaN | **NaN-reflexive `sameResult`** (no tolerance) |
| additive / multiplicative identity, `a*0` | exactly, on **finite** | keep finite-guarded (already done) |
| self-subtraction `a - a` | exactly, on **finite** | keep finite-guarded |
| associativity `+`, `*` | **no** — unbounded under cancellation | **do not run over floats** |
| distributivity | **no** — unbounded under cancellation | **do not run over floats** |
| `(a+b) - b == a` (subtraction inverse) | **no** — lossy | **do not run over floats** |

The kit's current instinct — not auto-running the algebraic chain for floats,
suppressing the fragile `Complex` laws — is therefore **more correct than §8.1.7
implies**. The reconciliation is *not* "make code match prose"; it is "implement
the sound subset in code, and correct the prose so it stops over-promising."

## 4. Work item A — prose corrections (book manuscript)

To apply to `manuscript/Chapter Outline/08 Conformance laws as properties.md`.

### §8.1.6 — replace the Complex-authority framing

> **Draft.** Because `Complex(x, 0)` embeds `Double`'s `x` faithfully **for finite
> values**, the two carriers compute the shared operations identically there — so
> a *finite* algebraic disagreement between them would be an oracle artifact, not
> real math. The carriers diverge only at the non-finite boundary, and they
> diverge because `Complex` is **lossier**: swift-numerics collapses every
> non-finite value — `inf` and `nan` alike — into a single "point at infinity,"
> so `Complex(nan, 0) == Complex(inf, 0)` is `true` where `Double.nan` and
> `Double.inf` stay distinct. That collapse is why `Complex`'s `==` is already
> `NaN`-reflexive; it is *not* evidence that `Complex` is "more correct." The
> justification for making `Double`'s oracle `NaN`-reflexive is the one from
> §8.1.5 — it is the right equivalence for an equational law — and consistency
> with `Complex` is a partial by-product (the two agree on `nan`-vs-`nan`, still
> disagree on `inf`-vs-`nan`), not a theorem you can lean on. Integers escape the
> hazard entirely: no `NaN`, so `==` is a genuine equivalence and the raw check is
> correct — their boundary case is *overflow* (Chapter 4), not the oracle.

### §8.1.7 — fix the tolerance claim

> **Draft.** Add a fourth row / caveat to the taxonomy: catastrophic cancellation
> makes associativity and distributivity differ by a **full magnitude**, so they
> read as "genuine" under a distance test yet are **expected** for floats — which
> is exactly why those laws are **excluded over floating-point**, not rescued by a
> tolerance. State plainly: `+` and `*` are commutative *exactly* (no tolerance
> needed, only `NaN`-reflexivity); associativity/distributivity hold to **no**
> tolerance and are not run over floats. The tolerance oracle resolves only the
> rounding of **well-conditioned** two-sided comparisons — it is not a general
> license to run any algebraic law over floats.

Revised taxonomy table:

| Failure mode | Example | Sides differ by… | Real bug? | Treatment |
|---|---|---|---|---|
| **Genuine algebraic** | `-` not commutative | a sign / full magnitude, at every scale | **Yes** | report the counterexample |
| **Well-conditioned rounding** | `+` reassociated on same-sign inputs | a few ULPs | No | tolerance oracle (`isApproximatelyEqual`) |
| **Oracle artifact** | two `NaN`s under `==` | *nothing* — both are `NaN` | No | `NaN`-reflexive `sameResult` |
| **Cancellation (inherent)** | `+` reassociated across a near-cancellation | up to a full magnitude | No — expected for floats | **exclude the law over floats** (no oracle fixes it) |

## 5. Work item B — code slice (kit)

Implement only the **sound** subset: a NaN-reflexive equivalence, used to run
**commutativity** (and to keep the finite-guarded identities) over floats/Complex.
Do **not** start running associativity/distributivity/subtraction-inverse over
floats.

**Design.** Add an injectable equivalence, default `==`:

```swift
// New: a "same result" equivalence, chosen for the oracle (separate from ==).
public typealias SameResult<Value> = @Sendable (Value, Value) -> Bool

// Default for exact carriers (Int, …): identity is ==.
// (Integers are exempt — no NaN — per §8.1.6.)
```

**Zero-dependency boundary (decided).** The main `PropertyLawKit` line keeps its
zero-`swift-numerics` footprint. The `Double`/`Float` equivalence is stdlib-only:

```swift
// stdlib-only; no swift-numerics.
@Sendable func floatSameResult<V: FloatingPoint>(_ a: V, _ b: V) -> Bool {
    (a.isNaN && b.isNaN) || a == b   // commutativity is EXACT, so == suffices here
}
```

Note: because the only law this slice runs over floats is **commutativity**
(exact modulo NaN), the equivalence needs **no tolerance term** — `==` plus
NaN-reflexivity is enough and is provably correct. A tolerance parameter is
deferred until/unless a genuinely well-conditioned two-sided law needs it; it is
*not* required to run commutativity, and it must not be used to smuggle in
associativity/distributivity.

The `Complex<Double>` equivalence lives in `PropertyLawComplex` (which already
imports `ComplexModule`) and uses `Complex`'s own reflexive `==`.

**Files touched:**

1. `Sources/PropertyLawKit/Public/NumericLaws.swift` — add `sameResult:` param
   (default `==`) to `checkNumericPropertyLaws`; use it in
   `multiplicationCommutativity` only.
2. `Sources/PropertyLawKit/Public/AdditiveArithmeticLaws.swift` — same for
   `additionCommutativity`.
3. `Sources/PropertyLawKit/Public/FloatingPointLaws.swift` — run *only*
   commutativity from the inherited chain, via `floatSameResult`; update the
   docstring that currently says the whole algebraic chain is skipped, to say the
   **runnable subset** (commutativity + finite-guarded identities) is run and the
   rest is excluded by design.
4. `Sources/PropertyLawComplex/` — provide the `Complex<Double>` `sameResult` and
   a `checkNumericPropertyLaws(..., sameResult:)` call that runs commutativity.
5. `Validation/Tests/ValidationPass2Tests/ComplexLawsTests.swift` — the
   associativity/distributivity/subtraction-inverse suppressions **stay**
   (those laws remain excluded); only note that commutativity now runs via the
   reflexive oracle rather than being at risk from NaN.
6. Tests — assert `floatSameResult` is NaN-reflexive and that commutativity of
   `+`/`*` over a NaN-inclusive `Double` generator passes, while a planted
   asymmetric operation still fails.

**Explicit non-goals:**

- Do **not** auto-run associativity, distributivity, or subtraction-inverse over
  floats. No oracle makes them hold.
- Do **not** add `swift-numerics` to the main line.
- Do **not** introduce a tolerance term for the commutativity slice — it is exact.

## 6. Recommendation

Apply Work item A (prose) and Work item B (code) together so the chapter and the
kit tell the same, correct story: **commutativity over floats is exact and only
needs NaN-reflexivity; associativity/distributivity are legitimately excluded, not
toleranced; and `Complex` is a lossier carrier, not the authority.**

## 7. Applied — what shipped

Both work items landed together. The as-built matches §4–§5 with two deviations,
both noted below.

**Work A (book manuscript, `08 Conformance laws as properties.md`).**
- §8.1.6 rewritten: `Complex` reframed as the *lossier* carrier (swift-numerics
  collapses `inf` *and* `nan` into one "point at infinity" —
  `Complex(nan,0) == Complex(inf,0)` is `true`), NaN-reflexivity justified by
  §8.1.5 alone, cross-carrier consistency demoted to a *partial* by-product
  (agree on `nan`-vs-`nan`, still disagree on `inf`-vs-`nan`). The false "diverge
  only at NaN" claim is removed.
- §8.1.7 rewritten: taxonomy is now **four** modes (added **Cancellation
  (inherent)**), the old "rounding = `+` not associative → a few ULPs" row is
  corrected to "well-conditioned rounding → same-sign reassociation", and the
  prose states plainly that commutativity is exact (no tolerance) while
  associativity/distributivity are *excluded over floats*, not toleranced.
- The two matching learning-objective bullets at the top of the chapter were
  updated to stay consistent (four modes; `Complex` lossier).

**Work B (kit).**
- `Sources/PropertyLawKit/Public/SameResult.swift` — `public typealias
  SameResult<Value>` + `public func floatSameResult<V: FloatingPoint>` (NaN-
  reflexive, **no tolerance term**, stdlib-only, no swift-numerics).
- `NumericLaws.swift` / `AdditiveArithmeticLaws.swift` — additive `sameResult:`
  parameter (default `==`), threaded into `multiplicationCommutativity` /
  `additionCommutativity` only. Non-breaking (defaulted).
- `FloatingPointLaws.swift` + new `FloatingPointCommutativityLaws.swift` — the
  FloatingPoint suite now runs two always-on commutativity laws
  (`FloatingPoint.additionCommutativity`, `FloatingPoint.multiplicationCommutativity`)
  via `floatSameResult`. Always-on count 9 → 11; associativity / distributivity /
  subtraction-inverse remain excluded.
- Tests: `Tests/PropertyLawKitTests/SameResultTests.swift` (reflexivity, no-mask-of-
  asymmetry via C-style `min`, commutativity over a NaN generator), plus updated
  counts/names in `FloatingPointLawsTests` / `BinaryFloatingPointLawsTests`.
- `Validation/.../ComplexLawsTests.swift` — suppressions unchanged; added
  `complexCommutativityIsExactOnNonFiniteInputs` documenting that `Complex` needs
  no injected oracle (its `==` is already reflexive).

**Deviation 1 — FloatingPoint laws are FP-namespaced, not reused from the
inherited chain.** §5 item 3 says "run only commutativity from the inherited
chain." As built, the FloatingPoint suite has its *own* two commutativity checks
named `FloatingPoint.additionCommutativity` / `FloatingPoint.multiplicationCommutativity`
(in `FloatingPointCommutativityLaws.swift`), rather than emitting the inherited
`Numeric.` / `AdditiveArithmetic.` names. Reason: every other FloatingPoint law is
`FloatingPoint.*`-namespaced and the suite's tests assert that prefix; reusing the
inherited checks would have mixed namespaces and broken
`defaultRunsInheritedFloatingPointFirst`. The public `sameResult:` params on
`checkNumericPropertyLaws` / `checkAdditiveArithmeticPropertyLaws` (§5 items 1–2)
still shipped for callers running those suites directly.

**Deviation 2 — no `Complex` `sameResult`; a value-level test instead.** §5 item 4
proposed a `Complex<Double>` `sameResult` in `PropertyLawComplex`. As built, none
was added: `Complex`'s own `==` is *already* NaN-reflexive, so `sameResult` would
be a redundant `{ $0 == $1 }`. Item 4's intent is instead captured by
`complexCommutativityIsExactOnNonFiniteInputs` (Validation Pass 2), which asserts
`+`/`*` commute bit-for-bit on non-finite `Complex` inputs. `PropertyLawComplex`
source is untouched (its zero-arithmetic-law surface is preserved).
