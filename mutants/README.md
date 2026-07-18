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

Each blinds a Strict-tier law by making its `property:` closure return `true`
unconditionally; the planted violator sails through, and the detection test that
demanded it be caught goes red. All three verified killed.

**A gap this corpus found (not shipped as a mutant):** blinding `Equatable.symmetry`
*survives* — the only asymmetric planted violator (`PriorityCompareEquatable`, whose
`==` is `>`) also breaks reflexivity, and `detectsAsymmetricEquality` asserts merely
"some `Equatable.` law," so reflexivity keeps catching it. There is no
symmetry-*only* violator (a `>=`-based type would be one), so the symmetry arm isn't
independently pinned. Worth closing by adding such a violator + a symmetry-specific
assertion; until then a symmetry regression would slip through.

## Adding a mutant

1. Make the buggy edit; 2. `git diff -- <file> > mutants/patches/<id>.patch`;
3. `git checkout -- <file>`; 4. add an entry to `manifest.json`.
