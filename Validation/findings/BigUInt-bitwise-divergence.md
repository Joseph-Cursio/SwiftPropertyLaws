# BigUInt's bitwise-NOT does not satisfy De Morgan's law

**Date discovered:** 2026-04-29
**Library:** [`attaswift/BigInt`](https://github.com/attaswift/BigInt) v5.7.0
**Affected type:** `BigUInt` (the unsigned arbitrary-precision integer)
**Affected laws:** `BinaryInteger.bitwiseDeMorgan`, `BinaryInteger.bitwiseDoubleNegation`
**Tier:** Strict
**Status:** Documented in `Validation/Tests/ValidationPass2Tests/BigIntLawsTests.swift` as `intentionalViolation` suppressions; tests pass with the caveat declared.

## What the kit found

Running `checkBinaryIntegerProtocolLaws(for: BigUInt.self, ...)` at `.standard` budget (1,000 trials) fires a Strict-tier violation on `BinaryInteger.bitwiseDeMorgan` within the first ~600 trials.

**Counterexample** (replay seed `JJV3lDSZMUfh1OXBSpPuu+SMxMVOzze42idwOvk3nK4=`):

```
x = 406803
y = 51776
x & y           = 0
~(x & y)        = 0
~x | ~y         = 18446744073709551615   (= UInt64.max)
```

De Morgan's law states `~(x & y) == ~x | ~y`. For `BigUInt` it does not hold.

## Why this happens

`BigUInt` stores its value as `[UInt64]` (a word array). The bitwise NOT operator `~` operates word-by-word over that storage, but the storage size depends on the value:

- `BigUInt(0)` is stored as the empty word array `[]`.
- `BigUInt(406803)` is stored as `[406803]` — one 64-bit word.

Tracing the counterexample:

| Expression | Storage | Result |
|---|---|---|
| `x & y` | both fit in one word | `BigUInt([0])` reduced to `BigUInt([])` = `0` |
| `~(x & y)` = `~BigUInt([])` | flip nothing | `BigUInt([])` = `0` |
| `~x` = `~BigUInt([406803])` | flip one word | `BigUInt([UInt64.max ^ 406803])` = ~406803 |
| `~y` = `~BigUInt([51776])` | flip one word | `BigUInt([UInt64.max ^ 51776])` = ~51776 |
| `~x \| ~y` | OR two one-word values | `BigUInt([UInt64.max])` = `18446744073709551615` |

The two sides of the equation operate on different storage sizes — there is no consistent "bit width" against which to flip. Stdlib's fixed-width unsigned types (`UInt`, `UInt64`, etc.) sidestep this by definition: every value uses exactly `Self.bitWidth` bits.

## Is this a bug?

It depends on what guarantees `BigUInt`'s public API is making. The kit's `bitwiseDeMorgan` law assumes the standard `BinaryInteger` contract holds — which for stdlib types it does, because they're all fixed-width.

For `BigUInt`, two reasonable design positions exist:

1. **`~` should produce a mathematically meaningful result.** Python's arbitrary-precision integer type chooses this: `~x = -(x+1)`, modeling "infinite-bit two's complement," which yields negative results. `BigUInt` can't go negative, so this option is closed off.

2. **`~` is a storage-level operation, with results that are useful as bit-pattern intermediates but not as algebraic identities.** This is what `BigUInt` ships. Useful for `~mask & value` patterns where the user knows the storage layout; problematic for algebraic identities like De Morgan's.

Position 2 is what `BigUInt` documents implicitly through its README's silence on the topic — there's no published guarantee that De Morgan's law holds. From a strict-mathematical standpoint, the law genuinely doesn't hold for arbitrary-precision unsigned without a fixed bit-width context.

## What this means for callers

**If you use `BigUInt` for arithmetic only** (`+`, `-`, `*`, `/`, `%`, comparison): unaffected. All the algebraic / division / shift / commutativity laws hold cleanly. Only the two kit laws that involve unary `~` are sensitive — `bitwiseDeMorgan` and `bitwiseDoubleNegation`, the two suppressed above. The kit's other seven `BinaryInteger` bitwise laws (`bitwiseAndCommutativity`, `bitwiseOrCommutativity`, `bitwiseXorSelfIsZero`, `bitwiseXorZeroIdentity`, `bitwiseAndIdempotence`, `bitwiseOrIdempotence`, `bitwiseAndDistributesOverOr`) never apply `~` and hold.

**The sensitivity is wider than the kit checks, though**, and that is worth knowing if you write your own bitwise laws: *any* law that applies unary `~` to a `BigUInt` inherits the same missing bit-width. The kit happens to encode only two of them. A third familiar identity — `a & ~0 == a`, the AND identity — is not a kit law but breaks just as hard, because `~0` needs an all-ones value and `BigUInt` has none: `~BigUInt(0) == 0`, so the law reads `a & 0 == a` and fails for every non-zero `a`. The rule of thumb is the `~`, not the law name.

**If you use `BigUInt` for bitwise operations across mixed magnitudes**: do not rely on De Morgan's law to refactor `~(a & b) ↔ ~a | ~b`. The storage-width difference between operands and intermediates can produce algebraically inconsistent results. Either keep the operation in a stdlib fixed-width type, or do the bitwise work explicitly word-by-word.

**`BigInt` (signed) is unaffected.** For signed arbitrary-precision, `~x = -(x+1)` is the standard arithmetic identity and doesn't depend on storage size — it's a value-level operation that happens to coincide with bit-flip on the typical encoding. The kit's `bigIntPassesBinaryIntegerLaws` test passes cleanly with no suppressions.

## How the kit handles this

The Pass 2 test file uses the kit's PRD §4.7 `intentionalViolation` suppression API:

```swift
// Validation/Tests/ValidationPass2Tests/BigIntLawsTests.swift
private static let arbitraryPrecisionBitwiseSuppressions: [LawSuppression] = [
    .intentionalViolation(
        LawIdentifier(protocolName: "BinaryInteger", lawName: "bitwiseDoubleNegation"),
        reason: "BigUInt: ~x storage-size depends on x's word count, so ~~x != x"
    ),
    .intentionalViolation(
        LawIdentifier(protocolName: "BinaryInteger", lawName: "bitwiseDeMorgan"),
        reason: "BigUInt: ~ has no consistent bit-width for arbitrary-precision unsigned"
    )
]
```

Each suppression carries:
- The exact law it covers (typed factory or string-based constructor).
- A free-text reason captured at the call site.
- The kind: `.intentionalViolation` means "the law would fire; treat the failure as expected."

If a future regression in `BigUInt` causes a *different* law to fail (one not on this list), it still fails loudly. If `BigUInt` is ever reworked to satisfy De Morgan, removing the suppression and rerunning the test would document the fix.

## Reproduction

```bash
cd Validation
swift package resolve   # pulls BigInt 5.7.0 + swift-numerics 1.1.1
swift test --filter "BigIntLawsTests"
```

To see the violation directly, comment out the `arbitraryPrecisionBitwiseSuppressions` reference in the `bigUIntPassesBinaryIntegerLaws` test and rerun.

## Worth filing upstream?

Maybe. The maintainer of `attaswift/BigInt` may already know this and consider it part of `BigUInt`'s contract. A README note ("BigUInt's bitwise NOT operates word-by-word and does not satisfy De Morgan's law for mixed-magnitude operands") would help future users avoid the trap, but it's not a code-level bug — the divergence is structural, not a thinko in the implementation.

Decision deferred. The Pass 2 test ships with documented suppressions either way.
