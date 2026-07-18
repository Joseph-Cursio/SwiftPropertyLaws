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

Each blinds a Strict-tier law by making its `property:` closure return `true`
unconditionally; the planted violator sails through, and the detection test that
demanded it be caught goes red. All four verified killed.

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
