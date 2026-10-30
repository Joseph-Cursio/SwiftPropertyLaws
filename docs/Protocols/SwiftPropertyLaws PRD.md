# Product Requirements Document

## SwiftPropertyLaws: Protocol Law Testing for Swift

**Version:** 0.3
**Status:** Describes the shipped kit, as of v4.10.0.
**Audience:** Open Source Contributors, Swift Ecosystem
**Supersedes:** v0.2 (in-place evolution; Appendix A is the v0.2 → v0.3 changelog) and v0.1 (Appendix B is the v0.1 → v0.2 changelog).

-----

## 1. Overview

Swift's protocol system creates a gap between structural conformance — which the compiler verifies — and semantic conformance, which it cannot. A type may declare `Equatable` while implementing `==` incorrectly. A `Comparable` implementation may violate transitivity. A `Codable` round-trip may silently lose data. None of these violations are detectable at compile time.

**SwiftPropertyLaws prevents subtle semantic bugs that escape code review and static analysis, without requiring developers to write or maintain property-based test infrastructure per type.**

This document specifies **SwiftPropertyLaws**, an open source Swift package delivering two separable but complementary contributions:

- **Contribution 1 — PropertyLawKit**: A curated library of protocol law property tests, generic over any conforming type, run through a public backend abstraction (§4.5).
- **Contribution 2 — PropertyLawMacro**: A Swift tooling layer (peer macros attached to a type, plus a command plugin for whole-module discovery) that detects protocol conformances and generates PropertyLawKit test suites, eliminating manual test wiring.

These two contributions are intentionally decoupled. PropertyLawKit has independent value. PropertyLawMacro depends on PropertyLawKit and adds automation. The macro and the plugin share one code-generation library, `PropertyLawCore`, and a handful of opt-in products carry laws and generators that need third-party dependencies (§4.10).

### 1.1 Why Now

Several recent shifts in the Swift ecosystem make this proposal feasible *and* timely:

- Swift macros (SE-0382 et al.) are stable enough to support compile-time generation reliably.
- Swift Testing supersedes XCTest as the official testing system, with an issue-recording and reporting model this kit can integrate with rather than work around.
- `swift-property-based` is active and battle-tested enough to serve as the backend without bootstrapping our own generator/shrinking infrastructure. SwiftQC exists as a second active package (different shrinking and async semantics) that demonstrates the abstraction surface is generalizable, even though the kit ships a single backend by design.
- The protocol surface itself has expanded (`Sendable`, `Identifiable`, `AdditiveArithmetic`, `Actor`) — more conformance contracts in flight, more value in checking them.
- Apple's broader correctness push (SwiftData, structured concurrency, ownership) signals an audience already attuned to "the compiler can't catch everything we care about."

-----

## 2. Problem Statement

### 2.1 The Structural/Semantic Gap

Swift's compiler enforces the *structural* contract of a protocol — the required methods and properties exist with correct signatures. It does not and cannot enforce the *semantic* contract — the behavioral protocol laws that a correct implementation is expected to satisfy.

Examples of semantic violations that compile without error:

```swift
// Violates symmetry: x == y may differ from y == x
extension MyType: Equatable {
    static func ==(lhs: MyType, rhs: MyType) -> Bool {
        return lhs.priority > rhs.priority
    }
}

// Violates hash/equality consistency
extension MyType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(UUID()) // always unique, breaks Dictionary
    }
}

// Violates round-trip fidelity
extension MyType: Codable {
    // encode omits a field; decode provides a default
    // decode(encode(x)) != x for non-default values
}
```

Each of these is a real class of production bug. None is caught by the type system.

### 2.2 The Activation Energy Problem

Developers who understand property-based testing could write these protocol law checks themselves. Most do not, because:

- Translating prose specifications (the `Equatable` documentation) into property tests requires deliberate effort per type.
- No standard library of protocol law checks exists for Swift.
- The connection between protocol conformance and testable properties is implicit, not surfaced by tooling.

### 2.3 The Ecosystem Gap

Adjacent ecosystems already solve this:

- **Rust** has `proptest` plus the `arbitrary` derive macro: type-directed generator synthesis bundled with a property runner.
- **Haskell** has QuickCheck plus community law libraries (`quickcheck-classes`, `checkers`) that ship the algebraic-law checks for `Eq`, `Ord`, `Functor`, `Monoid`, etc.

Swift has neither piece. The Swift property-based testing ecosystem has active packages (`swift-property-based`, SwiftQC) providing generation and shrinking infrastructure, but no protocol law library and no static-analysis layer connecting conformance declarations to property test generation. This gap is unoccupied.

-----

## 3. Goals and Non-Goals

### Goals

- Provide a complete, accurate library of semantic protocol law checks for Swift's core protocols, with each protocol law explicitly classified by strictness (see §4.2).
- Make protocol law checking available to any Swift project with a one-line addition per type, while honestly surfacing what *one line + a generator + interpretation* actually requires.
- Integrate naturally with `swift-property-based` as the default backend.
- Keep the backend swappable: `PropertyBackend` is public, with one shipped implementation (§4.5).
- Provide tooling (peer macros + a discovery command plugin) that eliminates manual protocol law registration through static analysis.
- Surface missing protocol conformances as opt-in suggestions, not just verify existing ones.
- Produce human-reviewable output, not silent automatic test generation.

### Non-Goals

- Replacing unit tests or general property-based testing.
- A general state-machine testing framework. The kit checks invariants and idempotence over action sequences driven through a caller's reducer (§4.9), and a few opt-in law families compare a concrete type against a model (§4.10), but it does not model arbitrary stateful systems.
- Formal verification.
- Full EvoSuite parity (domain-specific property inference is out of scope).
- Automatic code fixing of detected protocol law violations.
- Treating every protocol law as equally absolute — see strictness tiers, §4.2.

-----

## 4. Contribution 1: PropertyLawKit

### 4.1 Description

PropertyLawKit is a standalone Swift library of protocol law property tests. Each protocol's laws are exposed as a generic `async throws` function, `check<Protocol>PropertyLaws`, parameterized over a conforming type and run through the `PropertyBackend` abstraction (§4.5). Its only dependency is `swift-property-based`.

### 4.2 Protocol Law Strictness Tiers

Not every "law" associated with a Swift protocol is universally true in idiomatic Swift code. `Hashable` explicitly allows hash collisions; `Codable` round-trips are intentionally lossy for many real schemas; `Comparable` on floating-point intentionally fails for `NaN`. Presenting all such laws as absolute would generate false positives and erode trust.

Every check PropertyLawKit ships carries one of three explicit strictness tiers:

| Tier | Meaning | Behavior on violation under `.default` | Examples |
|---|---|---|---|
| **Strict** | Must hold for any correct conformance. A violation is a bug. | Throws, failing the test. | `Equatable` reflexivity, symmetry, transitivity; `Comparable` antisymmetry; `SetAlgebra` empty identity. |
| **Conventional** | Usually expected, but situationally violated by design. | Recorded, not thrown (see below). | `Codable` round-trip fidelity; `Comparable` totality; `Collection` non-mutation; `Hashable` stability within a process. |
| **Heuristic** | A useful signal, not a correctness claim. | Recorded, not thrown (see below). | `Hashable.distribution`. |

The tier appears in:

- The §4.3 tables (a `Tier` column per protocol).
- Every result (`CheckResult.tier`).
- The failure policy, set by `LawCheckOptions.enforcement`:
  - **`.default`.** A Strict violation throws `PropertyLawViolation`. A Conventional or Heuristic violation does not throw. On Swift 6.3 and later it is recorded as a Swift Testing issue of `.warning` severity, so the run prints it and the test passes. Swift Testing before 6.3 has no warning severity, so there the violation is recorded as an error, which marks the test failed even though nothing throws.
  - **`.strict`.** Every violation throws, whatever its tier. Under `.strict` a Heuristic violation fails the test too.
- Suppressed and intentional violations (§4.7) are never recorded or thrown under either mode.

This addresses the recurring critique that some advertised laws (lossy `Codable`, `NaN`, lazy collections) are intentionally violated in correct Swift code.

### 4.3 Supported Protocol Laws

**Inheritance semantics.** When a protocol extends another (e.g. `Hashable` extends `Equatable`, `Comparable` extends `Equatable`, `Collection` extends `Sequence`), each check function runs the **inherited laws by default**. Calling `checkHashablePropertyLaws` runs Equatable's laws *and* Hashable's:

```swift
// One call. Runs Equatable.{reflexivity, symmetry, transitivity, negationConsistency}
// AND Hashable.{equalityConsistency, stabilityWithinProcess, distribution}.
try await checkHashablePropertyLaws(for: MyType.self, using: MyType.gen())
```

This is the safe default. Property tests are expensive enough that "remember to chain inherited suites" cannot be a per-call developer responsibility — forgetting is a silent way to miss exactly the kind of semantic bugs this library exists to catch. Each inherited check produces its own `CheckResult` (`Equatable.symmetry`, `Hashable.equalityConsistency`, etc.) so test runner output stays attributable and a single suite's failure points at the actual offending law, not its descendant.

**Opt-out: `.ownOnly`.** Pass `laws: .ownOnly` to run only the protocol's own table — useful when the inherited suite has already run separately, when iterating on a single law, or when budget is tight and you've audited the inherited conformance:

```swift
// Skip Equatable's suite this run; we ran it explicitly above with a richer generator.
try await checkHashablePropertyLaws(
    for: MyType.self,
    using: MyType.gen(),
    laws: .ownOnly
)
```

**Plugin emits one call per type, the most specific one.** For a `Hashable` type, the Discovery plugin (§5.3) emits `checkHashable` and *not* a separate `checkEquatable`, since `checkHashable` already runs Equatable's suite by default. For a `Comparable & Codable` type it emits `checkComparable` (covers Equatable) plus `checkCodable`. This avoids the duplicate-runs-of-inherited-laws cost that the explicit-composition design would create when both calls appear in the same suite.

#### `Equatable`

| Protocol Law | Tier | Description |
|---|---|---|
| Reflexivity | Strict | `x == x` for all `x` |
| Symmetry | Strict | `x == y` implies `y == x` |
| Transitivity | Strict | `x == y` and `y == z` implies `x == z` |
| Negation consistency | Strict | `x != y` iff `!(x == y)` |

Floating-point `NaN` is the canonical intentional violation of reflexivity. `LawCheckOptions.allowNaN` does not affect these laws (it gates only the FloatingPoint NaN laws), so a type containing `Float`/`Double` should be checked with a finite-only generator, or have reflexivity marked as an intentional violation (§4.7).

Transitivity is conditional: it tests something only when two draws are equal. It reports how often that happened (`CheckResult.applications`, §4.6), and `LawCheckOptions.equalValuePairing` can make it find equal pairs a wide generator rarely draws (§4.4).

#### `Hashable` (extends `Equatable` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Hash/equality consistency | Strict | `x == y` implies `x.hashValue == y.hashValue` |
| Hash stability within a process | Conventional | `x.hashValue` constant across calls in one program run |
| Hash distribution | Heuristic | Hashes don't collapse to a small set across the generator |

`hashValue` is explicitly *not* required to be stable across runs (Swift randomizes hashing per launch); PropertyLawKit does not check cross-run stability. Hash/equality consistency is conditional like `Equatable.transitivity`, and reports its applications. The walked entry `checkHashablePropertyLaws(overEvery:)` (§4.4) runs every law except `distribution`, which is a statistic about a sample budget rather than a property of a space.

#### `Comparable` (extends `Equatable` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Irreflexivity | Strict | `!(x < x)` — `<` is a *strict* order, so a `<` written as `<=` fails. Stated over one value because the two-value laws see that bug only when both draws are equal |
| Antisymmetry | Strict | `x <= y` and `y <= x` implies `x == y` |
| Transitivity | Strict | `x <= y` and `y <= z` implies `x <= z` |
| Totality | Conventional | `x <= y` or `y <= x` for all `x`, `y` (relaxed for `Float`/`Double` because of `NaN`) |
| Operator consistency | Strict | `>`, `>=`, `<` are consistent with `<=` |

Antisymmetry and transitivity are conditional and report their applications.

#### `Strideable` (extends `Comparable` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Distance round-trip | Strict | `x.advanced(by: x.distance(to: y)) == y` |
| Advance round-trip | Strict | `x.distance(to: x.advanced(by: n)) == n` |
| Zero-advance identity | Strict | `x.advanced(by: .zero) == x` |
| Self-distance is zero | Strict | `x.distance(to: x) == .zero` |

`checkStrideablePropertyLaws` requires both a value generator and an explicit `strideGenerator: Generator<Value.Stride, _>` because `Stride` is an associated type (`Int` for `Int`/`Index`-style strideables, `TimeInterval` for `Date`, etc.). It runs the inherited `Comparable` suite first per the §4.3 inheritance convention.

#### `RawRepresentable`

| Protocol Law | Tier | Description |
|---|---|---|
| Round-trip fidelity | Strict | `T(rawValue: x.rawValue) == x` for every value the generator produces |

`RawRepresentable` is detected by the macro and discovery plugin only when written explicitly in the inheritance clause (`struct Foo: RawRepresentable`). Raw-value enums (`enum Status: String`) get the conformance synthesized by the compiler, but the macro/plugin sees only inheritance-clause syntax — they don't know `String` implies `RawRepresentable`. Users who want the law check on raw-value enums call `checkRawRepresentablePropertyLaws` manually. The API requires `Equatable` (the law uses `==`), but `RawRepresentable` does not extend `Equatable` in stdlib, so no inherited suite runs.

#### `LosslessStringConvertible`

| Protocol Law | Tier | Description |
|---|---|---|
| Round-trip fidelity | Strict | `T(String(describing: x)) == x` for every value the generator produces |

`String(describing:)` calls `CustomStringConvertible.description` (which `LosslessStringConvertible` inherits), so the law is the canonical "stringify, then parse, then compare" round-trip. The API requires `Equatable` for the comparison, but `LosslessStringConvertible` does not refine `Equatable` in stdlib — no inherited suite runs.

#### `Identifiable`

| Protocol Law | Tier | Description |
|---|---|---|
| Id stability within a process | Conventional | `x.id == x.id` for every value the generator produces — re-reads of `id` on the same instance return equal values |

The Conventional tier reflects that some app architectures legitimately compute `id` from mutable state; cross-process stability (the same logical entity getting the same id across program runs) is contextual and not checked. The kit's law tests within-process stability only — the canonical "no two reads agree" failure mode (e.g., `var id: UUID { UUID() }`) is what fires.

#### `CaseIterable`

| Protocol Law | Tier | Description |
|---|---|---|
| Exactly-once enumeration | Strict | `Set(allCases).count == allCases.count` — `allCases` lists each case exactly once |

For compiler-synthesized conformances on enums this holds by construction. The check exists as the self-test gate against hand-rolled `allCases` getters that accidentally drop or duplicate cases. The law is static (no per-sample property), so the `using:` parameter is accepted for API symmetry but ignored.

`CaseIterable` joins `IteratorProtocol` and `Strideable` on the macro/plugin's unemittable list — most `: CaseIterable` adoptions exist to expose `allCases` for list iteration rather than to test protocol-level correctness, and synthesized conformances never violate this law. Users invoke `checkCaseIterablePropertyLaws` manually when they want it.

#### `Codable`

| Protocol Law | Tier | Description |
|---|---|---|
| Round-trip fidelity | Conventional | `decode(encode(x))` matches `x` under the configured mode and codec |

`checkCodablePropertyLaws(for:using:config:options:)` takes a `CodableLawConfig(mode:codec:)`, defaulting to `.strict` and `.json`. The result is named `Codable.roundTripFidelity[<codec identifier>]`. The round-trip ships with three modes to accommodate real-world lossy encodings:

- `.strict` — exact equality required.
- `.semantic(equivalent:)` — caller-provided equivalence predicate, for cases where representational round-trip is intentionally lossy (canonicalized dates, normalized whitespace, etc.).
- `.partial(fields:)` — round-trip preserves a named subset of fields, for versioned schemas with default-bearing additions. Fields are typed `[PartialKeyPath<T>]`, not strings, so they survive renames and refactors:
  ```swift
  config: CodableLawConfig(mode: .partial(fields: [\Invoice.id, \Invoice.amount]))
  ```

The codec is `.json`, `.binaryPlist`, or any `CodableCodec(identifier:encode:decode:)`. Under `.semantic` and `.partial`, fields that diverge while the law still passes are recorded as near-misses (§4.6).

**Encoder independence** (the round-trip holding across every standard codec at once) is not built. Run the check once per codec instead.

#### `IteratorProtocol`

| Protocol Law | Tier | Description |
|---|---|---|
| Termination stability | Conventional | Once `next()` returns `nil`, subsequent calls also return `nil` (the iterator stays exhausted) |
| Single-pass yield | Conventional | An iterator yields each element at most once across a complete iteration |

`checkIteratorProtocolPropertyLaws` takes a generator of the host `Sequence`, since an iterator is obtained from one.

#### `Sequence`

| Protocol Law | Tier | Description |
|---|---|---|
| `underestimatedCount` lower bound | Strict | The iterator yields at least `underestimatedCount` elements |
| Multi-pass consistency | Conventional | For non-single-pass sequences, two fresh iterators yield the same elements in the same order |
| `makeIterator()` independence | Conventional | Calling `makeIterator()` does not perturb prior iterators or the sequence's observable state |

`Sequence` does not require multi-pass iteration in general; sequences that document themselves as single-pass (e.g. `AnyIterator` wrappers, network streams) pass `sequenceOptions: SequenceLawOptions(passing: .singlePass)` to suppress the multi-pass and `makeIterator()`-independence checks.

`checkSequencePropertyLaws` and `checkCollectionPropertyLaws` also have overloads taking `elementSameResult:` in place of `Element: Equatable`, for elements that cannot be `Equatable` — tuple elements such as `Dictionary`'s.

#### `Collection`

| Protocol Law | Tier | Description |
|---|---|---|
| Count consistency | Strict | `count` matches number of iterated elements |
| Index validity | Strict | All indices between `startIndex` and `endIndex` are valid |
| Non-mutation | Conventional | Iteration does not modify the collection (relaxed for lazy / view-like wrappers) |

`checkCollectionPropertyLaws` runs the `Sequence` and `IteratorProtocol` suites first per the §4.3 inheritance convention.

#### `BidirectionalCollection` (extends `Collection` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| `index(before:)` / `index(after:)` round-trip | Strict | `index(before: index(after: i)) == i` for any `i < endIndex` |
| `index(after:)` / `index(before:)` round-trip | Strict | `index(after: index(before: j)) == j` for any `j > startIndex` |
| Reverse-traversal consistency | Strict | Walking from `endIndex` via `index(before:)` to `startIndex` yields the reverse of the forward index sequence |

The reverse-traversal check compares index sequences rather than subscript-fetched elements: a broken subscript belongs to `Collection.indexValidity`, and subscripting from a buggy `index(before:)` (e.g. one that returns `endIndex` itself) traps before the law can ever assert anything.

#### `RandomAccessCollection` (extends `BidirectionalCollection` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Distance consistency | Strict | `distance(from: i, to: j)` equals the signed step count from `i` to `j` walked via `index(after:)` |
| Offset consistency | Strict | `index(i, offsetBy: n)` equals walking `n` forward (or `−n` backward) steps from `i` |
| Negative-offset inversion | Strict | `index(index(i, offsetBy: n), offsetBy: −n) == i` for any `n` keeping both indices in range |

The laws check value equivalence of the random-access methods against walking via `index(after:)` / `index(before:)`. Performance (the O(1) part of the contract) is *not* measured; only the answer the methods give. `Index: Comparable` is required by `Collection`, so the laws can't subtract indices and instead use *positions* in the walked-index sequence as ground truth.

#### `MutableCollection` (extends `Collection` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| `swapAt` swaps values | Strict | After `c.swapAt(i, j)`, `c[i]` equals the original `c[j]` and vice-versa |
| `swapAt` involution | Strict | `c.swapAt(i, j)` applied twice equals identity |

`MutableCollection`'s subscript setter is exercised through `swapAt(_:_:)`, whose default implementation goes through subscript get + set. A no-op setter fails `swapAtSwapsValues`; a value-transforming setter (doubling, clamping) fails both laws — the involution form surfaces the latter cleanly. The kit deliberately does *not* require an element generator: writing existing collection elements via `swapAt` is enough to exercise the setter contract.

#### `RangeReplaceableCollection` (extends `Collection` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Empty-init is empty | Strict | `Self()` produces an empty collection |
| Remove-at / insert round-trip | Strict | `remove(at: p)` then `insert(removed, at: p)` reproduces the original |
| `removeAll()` makes empty | Strict | `removeAll()` produces an empty collection |
| `replaceSubrange` applies edit | Strict | `replaceSubrange(startIndex..<endIndex, with: EmptyCollection())` clears the range |

`RangeReplaceableCollection`'s only mutating requirement is `replaceSubrange(_:with:)`; every other method (`append`, `insert`, `remove(at:)`, `removeAll(keepingCapacity:)`) has a default implementation routed through it. The kit's `replaceSubrangeAppliesEdit` law specifically guards against a no-op `replaceSubrange` — the round-trip and `removeAll` laws miss that case (the default `removeAll(keepingCapacity: false)` does `self = Self()` rather than calling `replaceSubrange`, and a no-op `remove(at:)` plus a no-op `insert(_:at:)` are compensating). The kit deliberately does *not* require an element generator; tests use the collection's own elements (snapshotted as `Array(sample)`) when a replacement sequence is needed.

The four refinements are independent siblings except for the `RandomAccessCollection → BidirectionalCollection → Collection` chain. A type that conforms to all four (e.g. `Array`) surfaces all four checks under the discovery plugin's most-specific dedupe; the user passes `.ownOnly` per call to avoid running Collection's three laws four times in CI.

#### `SetAlgebra`

| Protocol Law | Tier | Description |
|---|---|---|
| Union idempotence | Strict | `x.union(x) == x` |
| Intersection idempotence | Strict | `x.intersection(x) == x` |
| Union commutativity | Strict | `x.union(y) == y.union(x)` |
| Intersection commutativity | Strict | `x.intersection(y) == y.intersection(x)` |
| Empty identity | Strict | `x.union(Self()) == x` |
| Symmetric-difference self-empty | Strict | `x.symmetricDifference(x) == Self()` |
| Symmetric-difference empty identity | Strict | `x.symmetricDifference(Self()) == x` |
| Symmetric-difference commutativity | Strict | `x.symmetricDifference(y) == y.symmetricDifference(x)` |
| Symmetric-difference definition | Strict | `x.symmetricDifference(y) == x.union(y).subtracting(x.intersection(y))` |
| Union distributivity | Strict | `x.union(y.intersection(z)) == x.union(y).intersection(x.union(z))` |
| Intersection distributivity | Strict | `x.intersection(y.union(z)) == x.intersection(y).union(x.intersection(z))` |
| Union absorption | Strict | `x.union(x.intersection(y)) == x` |
| Intersection absorption | Strict | `x.intersection(x.union(y)) == x` |
| De Morgan for union | Strict | `x.subtracting(y.union(z)) == x.subtracting(y).intersection(x.subtracting(z))` |
| De Morgan for intersection | Strict | `x.subtracting(y.intersection(z)) == x.subtracting(y).union(x.subtracting(z))` |
| `formUnion` matches `union` | Strict | `var c = x; c.formUnion(y)` leaves `c == x.union(y)` |
| `formIntersection` matches `intersection` | Strict | likewise for `formIntersection` / `intersection` |
| `subtract` matches `subtracting` | Strict | likewise for `subtract` / `subtracting` |
| `formSymmetricDifference` matches `symmetricDifference` | Strict | likewise for `formSymmetricDifference` / `symmetricDifference` |

The four `symmetricDifference*` laws exist because the first five never exercise `symmetricDifference`. A git-archaeology pass found a `swift-collections` fix (`35349601`) where `_Bitmap.symmetricDifference` used `&` instead of `^`. `Validation/Tests/ValidationPass3Tests` pins the pre-fix parent and records that `TreeSet<Int>` passes every law there, because no public API reaches the buggy method (§8).

The six distributivity, absorption and De Morgan laws relate `union`, `intersection` and `subtracting` to each other, which no earlier law does. Without them a `subtracting` implemented as `symmetricDifference` passes, since the two agree whenever the subtrahend is a subset. `SetAlgebra` has no complement, so De Morgan is stated in relative (subtracting) form. The four `form*`/`subtract` laws check each mutating method against its non-mutating twin, because every other law uses the non-mutating operations only.

`SetAlgebra` does not formally extend `Equatable`, but the laws compare `Self == Self`, so the signature requires `Equatable`.

#### `AdditiveArithmetic`

| Protocol Law | Tier | Description |
|---|---|---|
| Addition associativity | Strict | `(x + y) + z == x + (y + z)` |
| Addition commutativity | Strict | `x + y == y + x` |
| Zero additive identity | Strict | `x + .zero == x` |
| Subtraction inverse | Strict | `(x + y) - y == x` |
| Self-subtraction is zero | Strict | `x - x == .zero` |

These exact-equality algebraic laws fire on integer-like types (`Int`, `Decimal`, BigInt). Floating-point types satisfy them only approximately due to IEEE-754 rounding — for `Float` / `Double`, use `checkFloatingPointPropertyLaws` instead. For FixedWidthInteger types, callers should pass a magnitude-bounded generator at `.standard` budget to avoid overflow traps.

`checkAdditiveArithmeticPropertyLaws` and `checkNumericPropertyLaws` take a `sameResult:` equivalence (default `==`) used only by the commutativity laws, the ones that hold exactly over floats. `floatSameResult` is the NaN-reflexive choice: `(a.isNaN && b.isNaN) || a == b`, with no tolerance term.

#### `Numeric` (extends `AdditiveArithmetic` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Multiplication associativity | Strict | `(x * y) * z == x * (y * z)` |
| Multiplication commutativity | Strict | `x * y == y * x` |
| One multiplicative identity | Strict | `x * 1 == x` |
| Zero annihilation | Strict | `x * 0 == 0` |
| Left distributivity | Strict | `x * (y + z) == x*y + x*z` |
| Right distributivity | Strict | `(x + y) * z == x*z + y*z` |

Three-way multiplication overflows under unbounded random sampling on `Int` / `Int32`; pass a bounded generator for fixed-width types at `.standard` budget. `Gen<T: FixedWidthInteger>.boundedForArithmetic()` does this.

#### `SignedNumeric` (extends `Numeric` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Negation involution | Strict | `-(-x) == x` |
| Additive inverse | Strict | `x + (-x) == .zero` |
| Negation distributes over addition | Strict | `-(x + y) == (-x) + (-y)` |
| Negate-mutation consistency | Strict | `var y = x; y.negate() ⇒ y == -x` |

`Value.min` traps under negation for two's-complement signed integers (`-Int.min` overflows); bounded generators that exclude `Value.min` avoid the trap.

#### `BinaryInteger` (extends `Numeric` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Division/multiplication round-trip | Strict | `y != 0 ⇒ (x / y) * y + (x % y) == x` |
| Remainder magnitude bound | Strict | `y != 0 ⇒ \|x % y\| < \|y\|` (or `x % y == 0`) |
| Self-division is one | Strict | `x != 0 ⇒ x / x == 1` |
| Division-by-one identity | Strict | `x / 1 == x` |
| Quotient-and-remainder consistency | Strict | `x.quotientAndRemainder(dividingBy: y) == (x/y, x%y)` |
| Bitwise AND idempotence | Strict | `x & x == x` |
| Bitwise OR idempotence | Strict | `x \| x == x` |
| Bitwise AND commutativity | Strict | `x & y == y & x` |
| Bitwise OR commutativity | Strict | `x \| y == y \| x` |
| Bitwise XOR self-is-zero | Strict | `x ^ x == 0` |
| Bitwise XOR zero-identity | Strict | `x ^ 0 == x` |
| Bitwise double-negation | Strict | `~~x == x` |
| Bitwise AND distributes over OR | Strict | `x & (y \| z) == (x & y) \| (x & z)` |
| Bitwise De Morgan | Strict | `~(x & y) == ~x \| ~y` |
| Shift-by-zero identity | Strict | `x << 0 == x && x >> 0 == x` |
| Trailing-zero bit-count range | Strict | `0 ≤ x.trailingZeroBitCount ≤ x.bitWidth` |

Division-related laws skip samples with denominator `0` (vacuous-true), so callers don't need to filter their own generators. Use `Gen<T: FixedWidthInteger>.boundedForArithmetic()` for fixed-width signed/unsigned types — it picks a per-type magnitude bound (`2^(bitWidth/4)`) so the inherited Numeric laws' triple multiplication doesn't overflow under random sampling. `nonzeroBitCount` is FixedWidthInteger-only, so its law lives there.

#### `SignedInteger` (extends `BinaryInteger` and `SignedNumeric` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Signum consistency | Strict | `x.signum() == 1` if `x > 0`, `-1` if `x < 0`, `0` if `x == 0` |

`SignedInteger` sits at the diamond between `BinaryInteger` and `SignedNumeric`. The `.all` dispatch runs `BinaryInteger`'s full inherited chain first (which includes `Numeric` and `AdditiveArithmetic`), then `SignedNumeric`'s own laws via `.ownOnly` to avoid double-running `Numeric`'s six laws. Most useful coverage comes from the inherited suites. The result is named `SignedInteger.signednessConsistency`.

#### `UnsignedInteger` (extends `BinaryInteger` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Non-negative | Strict | `x >= 0` |
| Magnitude is self | Strict | `x.magnitude == x` |

For stdlib `UInt*` types both laws hold by construction. The checks exist as the self-test gate against custom `UnsignedInteger` conformers that lie about signedness or whose `magnitude` typealias points somewhere non-trivial.

#### `FloatingPoint` (inherited algebraic chain not auto-run — see note)

| Protocol Law | Tier | When | Description |
|---|---|---|---|
| Infinity is infinite | Strict | always-on | `Self.infinity.isInfinite` |
| Negative-infinity comparison | Strict | always-on | `-Self.infinity < Self.infinity` |
| Zero is zero | Strict | always-on | `Self.zero.isZero` |
| Signed-zero equality | Strict | always-on | `Self.zero == -Self.zero` (IEEE-754 mandates equality) |
| Rounded-zero identity | Strict | always-on | `Self.zero.rounded() == Self.zero` |
| Additive inverse (finite) | Strict | always-on | `x.isFinite ⇒ x + (-x) == .zero` |
| Next-up/next-down round-trip | Strict | always-on | finite, non-extreme, non-zero ⇒ `x.nextUp.nextDown == x` |
| Sign matches less-than-zero | Strict | always-on | finite non-zero `x` ⇒ `x.sign` matches sign of `x < 0` |
| Absolute value non-negative | Strict | always-on | `!x.isNaN ⇒ x.magnitude >= 0` |
| Addition commutativity | Strict | always-on | `x + y` and `y + x` are the same result under `floatSameResult` |
| Multiplication commutativity | Strict | always-on | `x * y` and `y * x` are the same result under `floatSameResult` |
| NaN is NaN | Strict | `allowNaN` | `Self.nan.isNaN` |
| NaN inequality | Strict | `allowNaN` | `Self.nan != Self.nan` (IEEE-754) |
| NaN propagates addition | Strict | `allowNaN` | `(Self.nan + x).isNaN` |
| NaN propagates multiplication | Strict | `allowNaN` | `(Self.nan * x).isNaN` |
| NaN comparison is unordered | Strict | `allowNaN` | `!(Self.nan < x) && !(Self.nan > x) && !(Self.nan == x)` |

`checkFloatingPointPropertyLaws` does not run the inherited `AdditiveArithmetic` / `Numeric` / `SignedNumeric` chain. Those laws use exact `==`, and associativity, distributivity and subtraction-inverse fail on `Float` / `Double` by unbounded amounts under cancellation, so no equivalence rescues them. The suite runs the two algebraic laws that do hold exactly in IEEE-754, commutativity of `+` and `*`, compared with `floatSameResult` so that two NaNs count as the same result. The macro and plugin's most-specific dedupe drops the algebraic chain for `: FloatingPoint` types. Users wanting the full algebraic chain on a finite-only generator can call `checkSignedNumericPropertyLaws` directly.

The five NaN-domain laws are gated on `LawCheckOptions.allowNaN`. Default `false` skips them; set to `true` when explicitly testing IEEE-754 NaN behavior. The kit ships `Gen<Double>.doubleWithNaN()` and `Gen<Float>.floatWithNaN()` helpers that inject `Self.nan` on roughly 1 of every 20 trials, with seeded finite values — useful for exercising the always-on laws' NaN-skip guards even when `allowNaN` is left at the default.

#### `BinaryFloatingPoint` (extends `FloatingPoint` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Radix-2 constraint | Strict | `Self.radix == 2` (binade math depends on this) |
| Significand/exponent reconstruction | Strict | finite non-zero `x` ⇒ `Value(sign: x.sign, exponent: x.exponent, significand: x.significand) == x` |
| Binade membership | Strict | finite normal non-zero `x` ⇒ `\|x.binade\| <= \|x\| < 2·\|x.binade\|` |
| Converting from integer exactness | Strict | for `n` where `Value(exactly: n) != nil`: `Int(exactly: Value(exactly: n)!) == n` |

`x.binade` carries the sign of `x` in stdlib, and `binade.nextUp` returns the next *representable value* (not the next binade). The membership law uses `2·|binade|` as the upper bound and compares magnitudes so the law holds for negative samples. `allowNaN` propagates to the inherited FloatingPoint suite.

#### `FixedWidthInteger` (extends `BinaryInteger` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| Bit-width matches type | Strict | `x.bitWidth == Self.bitWidth` |
| Adding-reporting-overflow consistency | Strict | `x.addingReportingOverflow(y).partialValue == x &+ y` |
| Subtracting-reporting-overflow consistency | Strict | `x.subtractingReportingOverflow(y).partialValue == x &- y` |
| Multiplied-reporting-overflow consistency | Strict | `x.multipliedReportingOverflow(by: y).partialValue == x &* y` |
| Divided-reporting-overflow on div-by-zero | Strict | `x.dividedReportingOverflow(by: 0).overflow == true` |
| Wrapping arithmetic does not trap | Strict | `x &+ y`, `x &- y`, `x &* y` always produce a value (no trap) |
| Min/max bounds reachable | Strict | `Self.min <= x <= Self.max` |
| Byte-swapped involution | Strict | `x.byteSwapped.byteSwapped == x` |
| Nonzero-bit-count range | Strict | `0 ≤ x.nonzeroBitCount ≤ x.bitWidth` |

`FixedWidthInteger` is orthogonal to `SignedInteger` and `UnsignedInteger` — `Int32` conforms to both `FixedWidthInteger & SignedInteger`, `UInt` conforms to both `FixedWidthInteger & UnsignedInteger`. The discovery plugin emits both checks under most-specific dedupe (matching the `MutableCollection + RangeReplaceableCollection` sibling precedent). `nonzeroBitCount` is a FixedWidthInteger-only requirement; the corresponding law lives here rather than on `BinaryInteger`.

#### `StringProtocol` (extends `BidirectionalCollection` protocol laws)

| Protocol Law | Tier | Description |
|---|---|---|
| String-init round-trip | Strict | `String(String(s)) == String(s)` — converting a value to `String` is idempotent |
| Count matches String-init | Strict | `s.count == String(s).count` — character count preserved across the String conversion |
| isEmpty matches count zero | Strict | `s.isEmpty == (s.count == 0)` |
| Has prefix empty | Strict | `s.hasPrefix("") == true` |
| Has suffix empty | Strict | `s.hasSuffix("") == true` |
| Lowercased idempotent | Strict | `s.lowercased().lowercased() == s.lowercased()` |
| Uppercased idempotent | Strict | `s.uppercased().uppercased() == s.uppercased()` |
| UTF-8 view invariance | Strict | `Array(s.utf8) == Array(String(s).utf8)` — byte-level representation is invariant of the StringProtocol view |

Its conformers in stdlib are limited to `String` and `Substring`; custom conformers are essentially nonexistent in real-world Swift code. The kit's value here is twofold: a self-test gate that the framework's StringProtocol detection works, and an in-place property-based test of Apple's `String` / `Substring` implementations against algebraic invariants the stdlib documents informally. The Validation Pass 2 package's `StdlibStringProtocolLawsTests.swift` exercises both. Comparable / Hashable / LosslessStringConvertible, which StringProtocol also refines, are not auto-run; types declaring those still emit their own checks under most-specific dedupe.

#### Laws over methods and comparators

Two law families have no conformance to hang on.

**`checkTransformationPropertyLaws`** checks what stdlib *methods* promise over any `Sequence`. The closure-free entry (`Element: Comparable`) runs four Strict laws: `Transformation.sortedIdempotence` (`s.sorted().sorted() == s.sorted()`), `sortedIsNonDecreasing`, `sortedPreservesCount`, and `reversedInvolution`. The overload taking `functions: TransformationFunctions(first:second:predicate:)` runs four more over two endomorphisms and a predicate: `mapFusion` (`s.map(f).map(g) == s.map { g(f($0)) }`), `mapFilterCommutation` (`s.map(f).filter(p) == s.filter { p(f($0)) }.map(f)`), `lazyMapEquivalence` and `lazyFilterEquivalence`. The supplied closures must be pure. There is no planted violator: a protocol-extension method has no substitutable conformance to break.

**`checkStrictWeakOrderingLaws(over:by:options:)`** checks a supplied comparator — the `(T, T) -> Bool` that `sorted(by:)`, `min(by:)` and `max(by:)` take — rather than a type's `<`.

| Protocol Law | Tier | Description |
|---|---|---|
| Irreflexivity | Strict | `!compare(a, a)` |
| Asymmetry | Strict | `compare(a, b)` implies `!compare(b, a)` |
| Transitivity | Strict | `compare(a, b) && compare(b, c)` implies `compare(a, c)` |
| Incomparability transitivity | Strict | if `a`, `b` are incomparable and `b`, `c` are incomparable, so are `a`, `c` |

Two Conventional laws have their own entry points, because a comparator over a deliberately lossy key is supposed to fail them. `checkComparatorDiscriminates(over:by:distinct:options:)` (`StrictWeakOrdering.discrimination`) asks that no two distinct values be incomparable, which is what a reproducible order needs. `checkComparatorIsCongruent(over:by:options:)` (`StrictWeakOrdering.congruence`) asks that `a == b` imply `compare(a, x) == compare(b, x)`, i.e. that the comparator reads the value and not its storage. All three entry points also take `overEvery:` and `sampling:` (§4.4).

#### Coverage Scope

PropertyLawKit covers the stdlib protocols enumerated above and the kit-defined protocols in §4.9. The Swift Standard Library has roughly 54 public protocols (see `docs/Protocols/Swift Standard Library Protocols.md` for the full inventory); coverage is deliberate and audited rather than exhaustive. Every stdlib protocol identified as having testable laws has shipped. The rest are categorized as follows:

**Heuristic / deferred (laws are weak, contextual, or require runtime instrumentation):**

- `Sendable` — value semantics is not checkable from outside an arbitrary type. The kit-defined `ValueSemantic`, `StableIdentity` and `DefensiveCopy` protocols (§4.9) check it for a type that describes its own mutation surface.
- `LazySequenceProtocol`, `LazyCollectionProtocol` — laziness *is* a property to test (no eager evaluation) but requires instrumentation hooks. `Transformation.lazyMapEquivalence` and `lazyFilterEquivalence` check that the lazy views give the eager answer, not that they are lazy.
- `CustomStringConvertible`, `CustomDebugStringConvertible`, `TextOutputStreamable`, `TextOutputStream` — output formatting protocols; no semantic laws beyond "the conformance doesn't crash."
- `ExpressibleBy*` (the 10 literal protocols) — laws are structural rather than semantic; covered by the compiler's literal expansion.

**Permanently out of scope (no testable behavioral laws):**

- `AnyObject`, `AnyClass` — marker / class-constraint protocols.
- `Error`, `LocalizedError` — no behavioral contract beyond conformance and optional message accessors.
- `Encoder`, `Decoder`, `CodingKey` — infrastructure for `Codable` (which *is* covered).
- `CVarArg`, `MirrorPath`, `CustomReflectable` — bridging / reflection.
- `RandomNumberGenerator` — `next() -> UInt64` has no testable contract beyond the type signature.

Adding a protocol's laws means a `Public/<Protocol>Laws.swift` file in PropertyLawKit and, for the macro and plugin to detect it, a `KnownProtocol` case and its switch arms in PropertyLawCore. New protocols go into this Coverage Scope section before they go into the kit.

### 4.4 Usage API

Each suite is an `async throws` generic function called from an ordinary Swift Testing `@Test`. It returns `[CheckResult]` (§4.6, `@discardableResult`) and throws `PropertyLawViolation` when a violation escalates (§4.2). `using:` takes a `swift-property-based` `Generator<Value, _>`; there is no implicit generator. The default backend is `swift-property-based`:

```swift
import PropertyLawKit
import Testing

@Suite struct MyTypeConformanceTests {

    @Test func equatablePropertyLaws() async throws {
        try await checkEquatablePropertyLaws(
            for: MyType.self,
            using: MyType.gen(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    @Test func codablePropertyLaws() async throws {
        try await checkCodablePropertyLaws(
            for: MyType.self,
            using: MyType.gen(),
            config: CodableLawConfig(mode: .strict, codec: .json)
        )
    }
}
```

Settings shared by every suite live in `LawCheckOptions`: `budget`, `enforcement`, `seed`, `suppressions`, `backend`, `expectedReplayEnvironment`, `replayRelaxation`, `allowNaN` and `equalValuePairing`. Settings that vary by protocol stay separate parameters: `laws:` (inheritance, §4.3), Codable's `config:`, Sequence's `sequenceOptions:`, Strideable's `strideGenerator:`, the numeric suites' `sameResult:`.

#### Generators the kit ships

Beyond what `swift-property-based` provides: `Gen<T>.boundedForArithmetic()` for fixed-width integers, `Gen<Double>.doubleWithNaN()` and `Gen<Float>.floatWithNaN()`, `Gen<Unicode.Scalar>.unicodeScalar()` (banded across ASCII, Latin, BMP and astral ranges) and `.asciiScalar()`, and Foundation generators `Gen<Date>.date()`, `Gen<UUID>.uuid()`, `Gen<Data>.data(of:)`, `Gen<URL>.url()` and `Gen<Decimal>.decimal()`. `ActionSequenceFactory.actionSequence(from:length:statefulGuards:)` turns an action generator into an `[Action]` generator (default length `0...16`), and `actionSequence(forCaseIterable:length:statefulGuards:)` does the same for a `CaseIterable` action type. A `StatefulGuard` drops a candidate action that the history so far would not allow.

#### Trial Budget Tiers

Property-based testing on `Collection` or recursive structures at 10,000 trials per protocol law per type can dominate CI time. Every check accepts a `budget` (via `LawCheckOptions`):

| Budget | Trials | Intended use |
|---|---|---|
| `.sanity` | 100 | Local pre-commit, fast feedback |
| `.standard` | 1,000 | Default; PR-level CI |
| `.thorough` | 10,000 | Nightly / release branches |
| `.custom(trials:)` | n | Explicit override |

**These are effort tiers, not coverage claims.** Every case names a number of random draws and none says anything about the input space — a generator has no space to be exhaustive over. `TrialBudget.exhaustive(_:)` survives only as a deprecated factory returning `.custom(trials:)`. A run that genuinely covers its input space walks an `Enumeration` and reports `SpaceCoverage` (below and §4.6).

#### Bounded input spaces

A `Generator` is an unbounded stream of random draws. An `Enumeration<Element>` is a finite space with a known size, an order (smallest cases first, in contiguous buckets of equal size) and an address for every case. Spaces are built with `Every`:

- `Every.elements(_:in:size:)` — the elements of a collection.
- `Every.ranges(_:upTo:)` — every subrange of `0 ..< bound`, shortest first.
- `Every.subsets(_:of:)` — every subset of `0 ..< bound`, smallest first.
- `Every.sequences(_:of:upTo:)` — every sequence over an alphabet up to a length.
- `Every.product(_:_:)` and `Every.triples(of:)` — combinations, ordered by summed size.

Every constructor is closed-form, so no space is materialised. `Enumeration.prefix(_:)` caps a space and remembers its full size; `map(_:)` keeps order and addresses.

A space is consumed three ways:

- **Walk it.** `checkEveryCase(of:law:tier:options:satisfies:)` runs a property over every case, and the `overEvery:` entries run a whole suite over every case of a carrier: `checkEquatablePropertyLaws`, `checkHashablePropertyLaws`, `checkComparablePropertyLaws`, the five algebraic suites and `checkRingPropertyLaws` (§4.9), and the three comparator entries (§4.3). `checkInteractionInvariantPropertyLaws(…overEverySequenceUpTo:)` walks every action sequence up to a length. A walk needs no shrinker, because the first failing case is the smallest, and it reports `SpaceCoverage`. A walk consumes no randomness, so it prints no seed.
- **Sample it with its index.** `checkSampledCases(of:law:tier:options:satisfies:)` and the `sampling:` entries (Equatable, the algebraic suites, Ring, the comparator entries) draw at random but keep the index. A failure still shrinks toward the smallest case, and the run counts distinct cases against the space's size.
- **Bridge it.** `Enumeration.generator` is an ordinary `Generator`, for suites with no walked entry. It neither shrinks nor reports coverage. What it keeps is reach: a space's cases are defined, not constructed, so it produces configurations a construction-path generator never does.

`checkEveryCarrier(of:options:perCarrier:suite:)` varies the *subject* rather than the inputs: it runs a whole suite once per carrier. `perCarrier` (default `.sanity`) sets the per-carrier budget and `options.budget` is ignored, because otherwise the trial count multiplies by the carrier count. Results merge one per law, the walk stops at the first failing carrier, and `coverage` describes the carrier space.

#### Laws that need equal values

`Hashable.equalityConsistency`, `Equatable.transitivity` and `Comparable.antisymmetry` test something only when two draws are equal (or equivalent). Drawn independently, a wide generator almost never produces such a pair, and the law passes having tested nothing. `CheckResult.applications` reports how often the antecedent fired. `LawCheckOptions.equalValuePairing` changes how these three laws pair their draws; every other law ignores it:

- `.independent` (default) — each trial draws its own values.
- `.everyPairOfDraws` — draw the budget once and compare each draw with every earlier one (1,000 draws make 499,500 pairs). Transitivity follows the equal pairs into chains rather than testing every triple. The pool comes from one seeded stream, so the seed replays it.
- `.recentDraws(window:)` — compare each draw with the `window` draws before it; linear rather than quadratic.

Pooling is opt-in because its cost is quadratic and falls on whatever `==` the caller wrote. When a law pools, `trials` counts draws and `CheckResult.pairedDraws` records `(draws, pairs)`. A walk over an `Enumeration` reaches every pair already.

#### Generic Conformances

Real Swift code is generic-heavy: `Array<T>: Equatable where T: Equatable`, `Result<Success, Failure>: Equatable where Success: Equatable, Failure: Equatable`, user-defined `Container<T>`, and so on. PropertyLawKit checks generic conformances by binding type parameters at the call site:

```swift
// Conditional conformance on a user-defined container.
@Test func containerEquatablePropertyLaws() async throws {
    try await checkEquatablePropertyLaws(
        for: Container<Int>.self,
        using: Gen.container(of: Gen<Int>.int())
    )
    try await checkEquatablePropertyLaws(
        for: Container<String>.self,
        using: Gen.container(of: Gen<Character>.letterOrNumber.string(of: 0...8))
    )
}
```

The Discovery plugin does *not* enumerate generic instantiations — that's an unbounded search space. It also emits no check for a conditional conformance (`extension Container: Equatable where T: Equatable`), since an unconditional call would be wrong. Bind those by hand, as above.

Failures report which specific protocol law was violated, the strictness tier, and an explicit "not a proof" disclaimer:

```
✗ Equatable.symmetry  [Strict, 1000 trials]
  Counterexample: x = MyType(priority: 3), y = MyType(priority: 5); x == y → true, y == x → false
  Replay with seed: aKPPWDEafU0CGMDYHef/ETcbYUyjWQvRVP1DTNy6qJk=
  (Empirical evidence, not a proof.)
```

### 4.5 Backend Abstraction

PropertyLawKit defines a public `PropertyBackend` protocol so teams can swap the underlying runner. The signature accommodates async, throwing properties (the common case in Swift code under test) and `Sendable` types (Swift 6 strict concurrency):

```swift
public protocol PropertyBackend: Sendable {
    var identifier: String { get }

    func check<Input: Sendable>(
        trials: Int,
        seed: Seed?,
        sample: @Sendable (inout Xoshiro) -> Input,
        property: @Sendable (Input) async throws -> Bool
    ) async -> BackendCheckResult<Input>
}
```

The backend owns the trial loop and the random stream. `sample` draws one input from a seeded `Xoshiro`, so a backend never needs to know about `Generator`. It returns `.passed(trialsRun:initialSeed:)` or `.failed(trialsRun:initialSeed:failingInput:thrownError:)`. Everything above that stays in the kit: the law, its tier, shrinking a failing input, near-miss collection, suppression and formatting.

**Single-backend by design.** The kit ships only `SwiftPropertyBasedBackend`, the default for `LawCheckOptions.backend`, and deliberately does not chase a second implementation. The surface was shaped against `swift-property-based`, with SwiftQC's documented shrinking and async semantics as the design check that it generalizes. A second backend (e.g., a SwiftQC adapter) can drop in without changing law definitions, the moment one becomes a useful addition rather than a parity exercise.

Some checks bypass the backend: aggregate laws that judge a whole budget at once (`Hashable.distribution`, and the pooled equal-value laws of §4.4) draw from the kit's own seeded stream, and walks over an `Enumeration` run in a fixed order that no backend may vary.

#### Sendable Types

Every check constrains its value type to `Sendable`, and property closures are `@Sendable`, so inputs cross isolation boundaries safely under Swift 6 strict concurrency. Pure `Sendable` value types check identically to any other type.

`Sendable`'s own informal contract — value semantics, no shared mutable state — is not checkable for an arbitrary type. The kit-defined `ValueSemantic` protocol (§4.9) checks it for a type that describes its own mutation surface.

### 4.6 Confidence Reporting

Each protocol law check reports its result as a confidence artifact rather than a simple pass/fail. `CheckResult` carries:

| Field | Meaning |
|---|---|
| `protocolLaw` | The law's name, e.g. `Equatable.symmetry` |
| `tier` | `.strict`, `.conventional` or `.heuristic` |
| `trials` | Inputs drawn. For a pooled law (§4.4), draws rather than property evaluations |
| `seed` | The replay seed |
| `environment` | The replay fingerprint (below) |
| `outcome` | `.passed`, `.failed(counterexample:)`, `.suppressed(reason:)` or `.expectedViolation(reason:counterexample:)` |
| `nearMisses` | `[String]?` — inputs that came close to violating. `nil` means the law does not track them |
| `coverageHints` | `CoverageHints?` (`inputClasses`, `boundaryHits`), filled when the caller passes a `CoverageClassifier` (Equatable and Hashable take `coverage:`) |
| `shrunkFrom`, `shrinkSteps` | The original failing input, and how many shrink steps reached the reported one |
| `coverage` | `SpaceCoverage?` — `casesRun`, `spaceSize`, `isComplete`. `nil` for every sampled law: the check does not know its input space |
| `applications` | `Int?` — how often a conditional law's antecedent fired. `nil` for unconditional laws |
| `pairedDraws` | `(draws, pairs)` when a law pooled its draws |

This positions protocol law checks as *replayable experiments* — the seed and trial count are part of the permanent test record. `coverageHints` mitigates the "10,000 trials looks precise but is meaningless if all inputs are tiny integers" failure mode by recording which input classes the generator actually produced. `coverage` and `applications` say the same thing more directly: what fraction of a space a walk saw, and whether a conditional law tested anything at all. Both are reported, not enforced.

**Near-miss semantics.** A near-miss is an input where the property *almost* failed — surfacing brittleness even on green runs. Each law defines its own criterion, and two laws track one:

- `Codable.roundTripFidelity` under `.semantic` or `.partial` — each field where the decoded value differs from the original while the law still passes.
- `Collection.countConsistency` — an off-by-one between `count` and the number of iterated elements.

Every other law reports `nearMisses: nil` rather than an empty array, so callers distinguish "no near-misses" from "this law doesn't track them."

**Environment fingerprinting.** A seed is only as replayable as the environment that produced it. `CheckResult.environment` is an `Environment(swiftVersion:backendIdentity:generatorSchemaHash:)`. When `LawCheckOptions.expectedReplayEnvironment` is set, the kit compares it with the current environment before running any trial and throws `ReplayEnvironmentMismatch` on divergence, naming each differing field, rather than silently re-rolling a different test under the same seed string. Matching is `.exact` by default; `replayRelaxation` accepts `.matchBackendOnly` or `.matchSwiftVersionOnly`. `generatorSchemaHash` is currently the fixed placeholder `"m1-no-registry"`: there is no generator registry to hash, so in practice a mismatch is detected on Swift version and backend identity.

**Rendering.** A thrown `PropertyLawViolation` and a recorded warning (§4.2) both render each result the same way: a header line with the outcome glyph (`✓`, `✗`, `…` suppressed, `⊘` expected violation), the law, the tier and what the run covered (`1000 trials`, `walked all 512 cases`, `failed at case N of M`, or `1000 draws, 499500 pairs compared`); then the counterexample, near-misses, coverage hints and application count where present; then the replay seed, or for a walk `Deterministic walk — replays from the space, not a seed.`; then `(Empirical evidence, not a proof.)`. A conditional law that never applied says so: `Applied: never — the antecedent did not fire, so this pass tested nothing.`

### 4.7 Suppression and Customization

The biggest adoption risk for any law-checking tool is developer frustration from false positives. PropertyLawKit provides explicit, declarative suppression per law, per call:

```swift
// Skip a law: it does not run, and reports `.suppressed(reason:)` with zero trials.
// Intentional violation: the law runs, and a failure reports `.expectedViolation`
// instead of failing the test.
try await checkEquatablePropertyLaws(
    for: MyFloatWrapper.self,
    using: MyFloatWrapper.gen(),
    options: LawCheckOptions(suppressions: [
        .intentionalViolation(.equatable(.reflexivity), reason: "NaN by design")
    ])
)

// Customize the equivalence used by Codable round-trip checking.
try await checkCodablePropertyLaws(
    for: Invoice.self,
    using: Invoice.gen(),
    config: CodableLawConfig(mode: .semantic(equivalent: { $0.canonicalized == $1.canonicalized }))
)
```

`LawSuppression.skip(_:reason:)` and `.intentionalViolation(_:reason:)` take a `LawIdentifier`. Factories such as `.equatable(.reflexivity)` exist for the core stdlib suites; any law can be named with `LawIdentifier(protocolName:lawName:)`. Suppressions never escalate to a throw under any enforcement mode, and a suppressed or expected violation is never recorded as an issue. Each still appears in the returned results with its reason, so reviewers can spot policy drift.

In a file generated by the discovery plugin, a `// property-law-suppress: <protocol>_<TypeName>` marker suppresses one generated test and survives regeneration (§5.3).

### 4.8 Milestones

| Milestone | Deliverable | Status |
|---|---|---|
| M1 | `Equatable` and `Hashable` protocol laws (Strict tier only), `swift-property-based` backend, diagnostic output, trial budgets | Shipped |
| M2 | `Comparable` and `Codable` protocol laws; `Codable` strict/semantic/partial modes; Conventional tier introduced | Shipped |
| M3 | `Collection` and `SetAlgebra` protocol laws; suppression and intentional-violation API | Shipped |
| M4 | `PropertyBackend` public abstraction; finalized async/throws/Sendable property signature (single-backend by design — see §4.5) | Shipped |
| M5 | Confidence reporting upgrade — near-miss tracking, coverage hints, replay-environment validation, "not a proof" messaging, Heuristic tier | Shipped |

Work after M5 shipped as minor releases: the rest of the stdlib protocols in §4.3, the kit-defined protocols (§4.9), bounded input spaces and equal-value pairing (§4.4), and the opt-in products (§4.10).

### 4.9 Kit-defined Protocols

PropertyLawKit defines protocols where the Swift Standard Library leaves a useful gap. They ship from `import PropertyLawKit`. `Equatable` is required to *check* the laws but not to *declare* the conformance.

#### Algebraic protocols

The algebraic protocols are `KnownProtocol` cases, so the macro and the discovery plugin detect them and apply most-specific dedupe exactly as for stdlib protocols. The single-operation chain shares one `combine(_:_:)`:

`Semigroup → Monoid → CommutativeMonoid → Semilattice`, and `Monoid → Group`.

| Protocol | Refines | Requirement |
|---|---|---|
| `Semigroup` | — | `static func combine(_ lhs: Self, _ rhs: Self) -> Self` |
| `Monoid` | `Semigroup` | `static var identity: Self { get }` |
| `CommutativeMonoid` | `Monoid` | none — marker protocol |
| `Group` | `Monoid` | `static func inverse(_ value: Self) -> Self` |
| `Semilattice` | `CommutativeMonoid` | none — marker protocol |

| Protocol Law | Tier | Description |
|---|---|---|
| `Semigroup.combineAssociativity` | Strict | `combine(combine(a, b), c) == combine(a, combine(b, c))` |
| `Monoid.combineLeftIdentity` | Strict | `combine(.identity, a) == a` |
| `Monoid.combineRightIdentity` | Strict | `combine(a, .identity) == a` |
| `CommutativeMonoid.combineCommutativity` | Strict | `combine(a, b) == combine(b, a)` |
| `Group.combineLeftInverse` | Strict | `combine(inverse(a), a) == .identity` |
| `Group.combineRightInverse` | Strict | `combine(a, inverse(a)) == .identity` |
| `Semilattice.combineIdempotence` | Strict | `combine(a, a) == a` |

Each refinement's check runs its inherited chain by default (`laws: .ownOnly` opts out), and every check takes `using:`, `overEvery:` and `sampling:` (§4.4). Stdlib has no `Semigroup`, and `AdditiveArithmetic` doesn't fit the common merge-shape Swift type, whose operation is a `merge` / `combine` / `concat` / `union` rather than arithmetic `+`. The naming follows from that: `combine` rather than `+` avoids colliding with arithmetic operators, and `identity` rather than `empty` / `zero` avoids overlap with `RangeReplaceableCollection.init()` and `AdditiveArithmetic.zero`. `inverse(_:)` is a static method, not an `inverted()` instance method, so every witness has the same shape as `combine(_:_:)` and `identity`.

`Group` does not refine `CommutativeMonoid`: non-commutative groups (matrix groups, permutation groups) are valid, so the two are incomparable arms of the DAG and a type conforming to both surfaces both checks. Bounded join- and meet-semilattices share `Semilattice`, since the idempotence law is symmetric.

#### `Ring`

`Ring` is the kit's only two-operation protocol, a ring with unity. It stands alone: it neither refines nor is refined by the `combine` chain, because binding `combine` to one of its operations would leave the other lawless and collide with any single-operation conformance the type declares. A type that is both `Ring` and, through a different operation, `Monoid` surfaces both checks. It is for carriers whose ring operations are not named `+` / `*` (modular arithmetic, matrices, polynomials); stdlib `Numeric` / `BinaryInteger` already get ring-shaped coverage.

Requirements: `static var zero: Self`, `static var one: Self`, `static func add(_:_:) -> Self`, `static func multiply(_:_:) -> Self`, `static func negate(_:) -> Self`. Multiplication is not assumed commutative.

| Protocol Law | Tier | Description |
|---|---|---|
| `Ring.addAssociativity` | Strict | `add(add(a, b), c) == add(a, add(b, c))` |
| `Ring.addCommutativity` | Strict | `add(a, b) == add(b, a)` |
| `Ring.addLeftIdentity` | Strict | `add(.zero, a) == a` |
| `Ring.addRightIdentity` | Strict | `add(a, .zero) == a` |
| `Ring.addLeftInverse` | Strict | `add(negate(a), a) == .zero` |
| `Ring.addRightInverse` | Strict | `add(a, negate(a)) == .zero` |
| `Ring.multiplyAssociativity` | Strict | `multiply(multiply(a, b), c) == multiply(a, multiply(b, c))` |
| `Ring.multiplyLeftIdentity` | Strict | `multiply(.one, a) == a` |
| `Ring.multiplyRightIdentity` | Strict | `multiply(a, .one) == a` |
| `Ring.leftDistributivity` | Strict | `multiply(a, add(b, c)) == add(multiply(a, b), multiply(a, c))` |
| `Ring.rightDistributivity` | Strict | `multiply(add(a, b), c) == add(multiply(a, c), multiply(b, c))` |

`checkRingPropertyLaws` takes `using:`, `overEvery:` and `sampling:`, and has no `laws:` parameter since nothing is inherited.

**Roadmap.** `CommutativeGroup` is deferred: most everyday abelian groups are integers or floats under `+`, already covered by `AdditiveArithmetic` / `Numeric`, and a type that is both `CommutativeMonoid` and `Group` gets both checks today. `CommutativeSemigroup` is deferred likewise. `Functor` / `Applicative` / `Monad` are out of scope.

#### `InteractionInvariant` family

An invariant over the states a reducer can reach. The root protocol, `InteractionInvariant`, has `associatedtype State` and `static func invariantHolds(in state: State) -> Bool`. Four refinements add no requirements and only name the invariant's shape: `CardinalityInvariant`, `ReferentialIntegrityInvariant`, `BiconditionalInvariant` and `ConservationInvariant`. `ActionIdempotenceInvariant` requires `State: Equatable` and adds `associatedtype Action: Hashable` and `static var idempotentActions: Set<Action>`; its `invariantHolds` defaults to `true`.

- `checkInteractionInvariantPropertyLaws(for:initialState:reducer:length:statefulGuards:options:)` samples action sequences for a `CaseIterable` action type, applies them step by step, and checks the invariant after every step (`InteractionInvariant.invariantHoldsAfterEachStep`, Strict). Checking per step catches a transient violation a later step repairs. The `overEverySequenceUpTo:` overload walks every sequence up to a length instead, which reports the shortest reaching sequence.
- `checkActionIdempotenceInvariantPropertyLaws(for:initialState:reducer:length:statefulGuards:options:)` drives the reducer to a sampled reachable state, then checks `reducer(reducer(s, a), a) == reducer(s, a)` for each idempotent action (`ActionIdempotenceInvariant.doubleApplicationEqualsSingle`, Strict).
- Both have overloads taking an `async` reducer.
- `checkInvariantIsFalsifiable(for:using:options:)` (`InteractionInvariant.isFalsifiable`, Conventional) checks the specification rather than the code: it samples states from a caller's generator without running the reducer and asks that the invariant reject at least one. An invariant that accepts every state constrains nothing, and passes every other law. It is Conventional because a generator too narrow to build a violating state makes a correct invariant look vacuous.

#### `ValueSemantic`, `StableIdentity` and `DefensiveCopy`

Three protocols for checking copy and identity behavior. Each conformer describes its own mutation surface as an `associatedtype Mutation: CaseIterable & Sendable` with a static `apply`, and supplies `static func makeProbe() -> Self`, which must return an equal-valued, independently constructed instance on every call. The harness samples a script of mutations through `ActionSequenceFactory` and compares against a second probe, never against a copy of the first, since a leaky type's copies share the storage that leaks.

| Protocol | Refines | Laws (all Strict) |
|---|---|---|
| `ValueSemantic` | `Equatable` | `ValueSemantic.copyMutationDoesNotLeak` — mutating a copy leaves the original unchanged; `copyMutationDoesNotLeakUnderInterleaving` — after a copy is mutated, the original's own later mutations still match an interference-free replay |
| `StableIdentity` | `AnyObject, Hashable` | `StableIdentity.hashStableUnderMutation`, `equalityStableUnderMutation` — mutation does not change `hashValue` or equality to an independent twin, so the object is safe as a `Set` / `Dictionary` key |
| `DefensiveCopy` | `AnyObject, Equatable` | `DefensiveCopy.copyIsDistinctInstance` — `copyUnderTest()` returns a new object; `copyIsIndependent` — mutating the copy does not affect the original |

`DefensiveCopy` also requires `func copyUnderTest() -> Self`, which calls the type's real `copy()` / `clone()`. For the two class protocols, `apply` takes the target without `inout`. The entry points are `checkValueSemanticPropertyLaws`, `checkStableIdentityPropertyLaws` and `checkDefensiveCopyPropertyLaws`, each `(for:length:options:)`. A failing mutation script shrinks to the minimal reproduction. None of the three is a `KnownProtocol` case; they are wired by their own peer macros (§5.6).

### 4.10 Opt-in Products

Laws and generators that need a third-party dependency ship as separate products, so `PropertyLawKit` itself depends only on `swift-property-based`. Each is imported explicitly.

| Product | Adds a dependency on | What it provides |
|---|---|---|
| `PropertyLawComplex` | `swift-numerics` | `Gen<Complex<Double>>.edgeCaseBiased()`: 90% finite values, 10% drawn from a curated set of twelve edge cases |
| `PropertyLawCollections` | `swift-collections` | Generators for `Deque`, `OrderedSet`, `OrderedDictionary`, `BitSet`, `Heap`, `TreeSet` and `TreeDictionary`; `DequeLayouts.everyLayout()`, an `Enumeration` of deque buffer layouts including wrapped ones; and three law families over concrete types: `checkHeapPropertyLaws` (draining matches a sorted model), `checkDequeSymmetryPropertyLaws` (front-end operations mirror the back end and agree with an array model) and `checkOrderPreservationPropertyLaws` (`OrderedSet` order) |
| `PropertyLawAsync` | `swift-async-algorithms` | `checkAsyncSequencePropertyLaws` — nine clock-free laws over a source array lifted to an async sequence: chunks, adjacent pairs, `removeDuplicates`, interspersed and compacted agree with sync models; `merge` preserves the element multiset; `zip` matches sync `zip`; an exhausted iterator stays exhausted. `checkTimedAsyncSequencePropertyLaws` — four `debounce` and cancellation laws run in virtual time on the product's own scheduler, which advances the clock only when every task is idle, so a run cannot hang |
| `PropertyLawSyntax` | `swift-syntax` (`SwiftParser`) | `Gen<Syntax>.syntax()` and `Gen<T>.syntaxNode()` for any typed node, drawn from a pool of parsed trees kept alive so node identities stay distinct; `static func gen()` on `Syntax`, `ExprSyntax`, `DeclSyntax`, `StmtSyntax`, `PatternSyntax`, `TypeSyntax` and `TokenSyntax`, so derived code that spells `T.gen()` resolves |
| `PropertyLawMinimalTypes` | — | `MinimalSequence`, `MinimalCollection` and `MinimalBidirectionalCollection`, the weakest legal conformances, for running a suite against something that is not `Array`; plus a minimal codec |

The collection and async law families are stated over concrete types with no protocol to substitute, so the planted-violator gate (§8) does not apply to them: they test the dependency, not a user's conformance.

-----

## 5. Contribution 2: PropertyLawMacro

### 5.1 Description

PropertyLawMacro is a tooling layer that uses SwiftSyntax to statically analyze source files, detect protocol conformances, and automatically generate PropertyLawKit test suites. It eliminates the need to manually write `checkEquatablePropertyLaws(...)` calls for each conforming type.

The generated code is *human-reviewable*: macro expansions can be inspected in the editor, and the discovery plugin writes a file the developer reviews, approves, and commits. This preserves developer agency and avoids the "magic that occasionally breaks" failure mode.

### 5.2 Layered Scope

PropertyLawMacro is deliberately layered. The Core layer is the MVP — small, narrow, and the only thing required to deliver value. The Advisory layer is opt-in.

| Layer | Capabilities | Default state |
|---|---|---|
| **Core** | Conformance → test suite generation (peer macros and discovery plugin), generator derivation | Always on |
| **Advisory** | Missing-conformance suggestions; cross-function round-trip discovery | Off by default; `--advisory` to enable |

The architecture diagram (§6) reflects this layering. Users adopting only Core get a deterministic, low-noise tool. Advisory output goes to stderr and never touches the generated file, so it can be evaluated without affecting Core's signal-to-noise ratio.

### 5.3 Core: Two Operating Modes

#### Macro Mode (compile-time, per type)

`@PropertyLawSuite` is a peer macro attached to a type declaration. Swift macros see only their decoratee's syntax, so the macro works one type at a time. It reads the type's inheritance clause, applies the most-specific dedupe (§4.3), derives a generator (§5.7), and emits a sibling `struct <TypeName>PropertyLawTests` holding one `@Test` per surviving protocol:

```swift
@PropertyLawSuite
struct Foo: Equatable, Hashable {
    let value: Int
}

// Expands, as a peer of Foo, to:
struct FooPropertyLawTests {
    @Test func hashable_Foo() async throws {
        try await checkHashablePropertyLaws(
            for: Foo.self,
            using: Gen<Int>.int().map { Foo(value: $0) }
        )
    }
}
```

The macro derives with the type's own syntax only, so a member whose type is another custom type does not derive here (the plugin resolves those). A type with no derivable generator raises a `cannotDeriveGenerator` diagnostic and emits a `.todo` stub (§5.7).

#### Discovery Mode (Swift Package Plugin, whole-module)

Whole-module discovery is delivered as a **command plugin**, not a macro: macros are file-local and cannot scan a module's other files, while a plugin has the file-system access required. It is run on demand, not as a build step.

```bash
swift package propertylawcheck discover --target MyModule
```

| Flag | Effect |
|---|---|
| `--target <name>` | Required. The target to scan. |
| `--output <path>` | Where to write. Default `Tests/<Target>Tests/PropertyLawTests.generated.swift`. |
| `--extra-import <Module>` | Repeatable. Adds a plain `import` for a module that supplies generators rather than types (e.g. `PropertyLawSyntax`). Never inferred, because guessing an opt-in product's import breaks every project that lacks it. |
| `--scaffold-out <path>` | Also writes a separate, non-compiling file of `gen()` stubs for `.todo` types, with derivable slots filled and `<#…#>` placeholders for the rest. |
| `--advisory` | Enables the Advisory suggestions (§5.4, §5.5) on stderr. |
| `--advisory-min low\|medium\|high` | Confidence floor for Advisory output. Default `high`. |

The plugin also passes the source files of the target's transitive dependencies to the scan as context, for declarations only. Context tells the scan what a type this target merely extends looks like and which module declares it; context types get no suites of their own.

Output is clearly marked as generated and includes provenance. Paths print as the plugin passed them:

```swift
// GENERATED by PropertyLawDiscoveryPlugin — DO NOT EDIT outside
// `// property-law-suppress: <protocol>_<TypeName>` markers.
//
// Target: MyModule
// Types detected: 1
// Re-run: swift package propertylawcheck discover --target MyModule

import Testing
import PropertyLawKit
@testable import MyModule

// MyType — Sources/MyModule/MyType.swift:13 (primary)
@Suite struct MyTypePropertyLawTests {
    @Test func comparable_MyType() async throws {
        try await checkComparablePropertyLaws(
            for: MyType.self,
            using: Gen<Int>.int().map { MyType(rank: $0) }
        )
    }

    @Test func codable_MyType() async throws {
        try await checkCodablePropertyLaws(
            for: MyType.self,
            using: Gen<Int>.int().map { MyType(rank: $0) }
        )
    }
}
```

The module under test is imported `@testable`, so `internal` types are reachable. Modules that declare foreign types the file names get a plain `import`, as do modules a derived generator needs and any `--extra-import`. A nested type is named by its qualified name (`BitSet.Counted`) and its suite by a sanitized identifier (`BitSet_CountedPropertyLawTests`). Three kinds of type are detected but get no suite, listed in the header and the summary with the reason: `private` / `fileprivate` types (not nameable from another file), non-`public` types declared in another module, and `public` types with no `Sendable` conformance (every check requires `Sendable`).

#### Developer Workflow

1. Run the discovery plugin (locally or wired into CI).
2. Review the generated `*.generated.swift` file as a normal PR.
3. Commit the generated file. Re-run the plugin when types or conformances change. Output is deterministic, so a regeneration shows up as a diff. The file is rewritten each run: hand edits do not survive, suppression markers do.
4. Suppress a noisy or wrong test by adding `// property-law-suppress: <protocol>_<TypeName>` (e.g. `hashable_MyType`) to the generated file. The next regeneration replaces that test with a comment stub that keeps the marker, so suppression deltas show up in diff review.

### 5.4 Advisory: Missing Conformance Suggestions (opt-in)

Beyond verifying declared conformances, the discovery plugin can suggest *potentially missing* conformances based on structural analysis. **This is opt-in (`--advisory` flag), not default.** It is informational output on stderr, never a test failure:

```
PropertyLawDiscoveryTool: 1 advisory suggestion(s):
  note: MyType defines `func encode(to:)` and `init(from:)` but does not declare Codable.
        Consider conforming and running checkCodablePropertyLaws to verify the laws hold.
        confidence: high
```

Four detectors ship, each High confidence and each firing only when the protocol is not already declared: `Codable` (both `encode(to:)` and `init(from:)`), `Equatable` (`static func ==`), `Hashable` (`func hash(into:)`) and `Comparable` (`static func <`). An `Equatable` suggestion is dropped when `Hashable` or `Comparable` is suggested for the same type. Suggestions always require human judgment to act on.

### 5.5 Advisory: Cross-Function Discovery (opt-in)

With `--advisory`, the plugin also detects function pairs with inverse type signatures and suggests round-trip properties:

- Detection criteria: functions `f: T → U` and `g: U → T` among one type's members, or among the module's free functions. Generic functions are skipped.
- Confidence: **High** when the signatures invert *and* either the names match a curated pair (`encode`/`decode`, `serialize`/`deserialize`, `encrypt`/`decrypt`, `compress`/`decompress`, `marshal`/`unmarshal`, `pack`/`unpack`, `parse`/`format`, `push`/`pop`) or both functions carry the same `@Discoverable(group:)`. **Medium** on signature inversion alone. **Low** on a name or group match without inversion.
- `@Discoverable(group: "serialization")` is a marker peer macro that emits nothing; it exists to be read here.

The default floor is High, so Medium and Low suggestions appear only with `--advisory-min`. Adding a curated name pair requires a maintainer commit.

### 5.6 Peer Macros for Kit-defined Protocols

Four more peer macros wire the kit-defined protocols of §4.9, whose harnesses need members a stdlib conformance does not have. Each emits a sibling struct with one `@Test` and raises a diagnostic when the type's primary declaration does not list the protocol:

- `@InteractionInvariantTests` — on an `InteractionInvariant`-family conformer that defines `static var initialState` and `static var reducer`. Emits `<TypeName>InteractionInvariantTests`, calling `checkActionIdempotenceInvariantPropertyLaws` for an `ActionIdempotenceInvariant` conformer and `checkInteractionInvariantPropertyLaws` otherwise. A missing member is a compile error in the emitted code.
- `@ValueSemanticTests`, `@StableIdentityTests`, `@DefensiveCopyTests` — emit `<TypeName>ValueSemanticTests` (and so on), calling the matching harness with `for: TypeName.self`.

### 5.7 Generator Derivation

Generator derivation is the single highest execution risk in this proposal — a weak generator produces green tests that are not meaningful, defeating the entire premise. Derivation is therefore explicit, prioritized, and visible: the derived expression is written into the generated code, and when nothing derives the output does not compile.

One implementation serves every consumer: `DerivationStrategist.strategy(for:resolve:emissionSite:)` in `PropertyLawCore`, called by the macro, the discovery plugin and downstream tools. It returns a `DerivationStrategy`, which `GeneratorExpressionEmitter` renders as the `using:` expression. The plugin supplies `resolve:` from a `GeneratorResolver` over every type it scanned, so member types declared elsewhere in the module derive too. The macro has no such universe.

#### Derivation Priority Order

For type `T`, the strategist tries these in order, falling through to the next on failure:

1. **Explicit `gen()`** — a `static func gen()` on the type, found in the primary body by the macro and anywhere in the module by the plugin. Wins unconditionally; emitted as `T.gen()`.
2. **`CaseIterable` enum** — `Gen<T?>.element(of: T.allCases).compactMap { $0 }`. (`Gen.element(of:)` yields an optional, which is why the `Gen<T?>` spelling.)
3. **Memberwise** — a struct with no user `init` in its primary body, every stored property resolving to a generator: `zip(g1, g2, …).map { T(p1: $0.0, p2: $0.1, …) }`, or `g.map { T(p: $0) }` for one member. Member types may be the stdlib raw types (the integer family, `Bool`, `Double`, `Float`, `String`), known value types (`Character`, `Date`, `UUID`, `Data`, `URL`, `Decimal`, `Unicode.Scalar`, `Substring`), a few typealiases (`TimeInterval`, `CGFloat`, `unichar` and others), `Optional`, `Array`, `ArraySlice`, `Set` and `Dictionary` of those, and on the plugin path other types in the module. Up to 100 members, by nesting `zip` groups of ten. Declined when a stored property's access level puts the synthesized initializer out of reach of the emitted code.
4. **Initializer-based** — a struct (or a class declaring `Sendable`) with a user `init`: lift through the first callable initializer whose parameters all resolve. Initializers are declined when they are, among others, `private` / `fileprivate`, failable or throwing, parameterless, capacity-only (they would draw a constant), `_`-labelled (private storage whose arguments must jointly hold an invariant), or ones that state preconditions on their arguments.
5. **Stateless** — a struct with no stored properties and no `init` or a callable `init()`: `Gen.always(T())`. With one value, the constant is the whole domain.
6. **Enum case enumeration** — an enum whose cases were captured: `Gen.oneOf` over one generator per case, `Gen.always(T.c)` for payload-free cases and payloads derived like members. It comes before raw-value derivation because that is a filter that, for a `String`-backed enum, effectively never terminates.
7. **Raw value** — fallback for a raw-value enum whose cases were not captured: the raw-type generator `.compactMap { T(rawValue: $0) }`. Still a filter, so usable only where the raw domain is small and densely covered.
8. **No generator available** — emit `T.gen()` followed by the comment `` // TODO: no generator derived — supply `static func gen()` (this line will not compile) ``. The missing symbol is a compile error that pins the user's attention; silent fallthrough is more dangerous. The macro raises a `cannotDeriveGenerator` diagnostic carrying the strategist's reason, which names the member, initializer parameter or enum case that failed. `GeneratorResolver.resolutionFailure(forTypeName:within:)` says why a type did not resolve.

#### Recursive Types

A self-reference under a wrapper — `[Self]`, `Self?`, `Set<Self>`, `[K: Self]` — derives on the plugin path as a depth-budgeted helper function whose base case collapses the wrapper to `[]` or `nil`. A bare recursive payload (`indirect case add(Expr, Expr)`) has no wrapper to terminate it and stays `.todo`, rather than becoming a generator that diverges or always returns the base case.

#### Override Mechanism

The developer always wins. A `static func gen()` on the type shadows derivation everywhere a stub is emitted for that type.

#### Failure Telemetry

When derivation falls back to `.todo`, the discovery plugin's summary lists the type and buckets the `.todo` types by reason (user `init` blocking memberwise, unresolved member type, enum payload unresolved, and so on), so the dominant derivation gap is visible, not buried. `--scaffold-out` turns those types into partial stubs.

### 5.8 Milestones

| Milestone | Deliverable | Layer | Status |
|---|---|---|---|
| M1 | SwiftSyntax conformance detection, `@PropertyLawSuite` peer macro, diagnostic emission | Core | Shipped |
| M2 | Swift Package Plugin discovery mode, generated file output with provenance, suppression markers preserved across regeneration | Core | Shipped |
| M3 | Generator derivation with priority order, `.todo` stubs, derivation-gap telemetry | Core | Shipped |
| M4 | Missing-conformance suggestions (opt-in, confidence-scored) | Advisory | Shipped |
| M5 | Cross-function round-trip discovery (opt-in) | Advisory | Shipped |

Later releases extended derivation (§5.7) and added the peer macros of §5.6.

-----

## 6. Architecture Overview

```
┌──────────────────────────────┐  ┌──────────────────────────────┐
│ PropertyLawMacro             │  │ Discovery plugin + tool      │
│ @PropertyLawSuite            │  │ propertylawcheck discover    │
│ §5.6 peer macros             │  │ Advisory: --advisory         │
│ @Discoverable marker         │  │                              │
└──────────────┬───────────────┘  └──────────────┬───────────────┘
               │ both build on                   │
┌──────────────▼─────────────────────────────────▼───────────────┐
│ PropertyLawCore (no dependencies)                              │
│ KnownProtocol · DerivationStrategist · GeneratorResolver ·     │
│ GeneratorExpressionEmitter                                     │
│ (+ PropertyLawSyntaxSupport: shared SwiftSyntax inspection)    │
└──────────────────────────────┬─────────────────────────────────┘
                               │ generated code calls into
┌──────────────────────────────▼─────────────────────────────────┐
│ PropertyLawKit                                                 │
│ check…PropertyLaws for stdlib and kit-defined protocols        │
│ Strictness tiers · LawCheckOptions · suppression               │
│ Trial budgets · Enumeration / SpaceCoverage · CheckResult      │
└──────────────────────────────┬─────────────────────────────────┘
                               │ runs sampled laws via
┌──────────────────────────────▼─────────────────────────────────┐
│ PropertyBackend (public)                                       │
│ SwiftPropertyBasedBackend — the single shipped backend         │
└────────────────────────────────────────────────────────────────┘

Opt-in products (§4.10) build on PropertyLawKit, each adding one
third-party dependency: PropertyLawComplex, PropertyLawCollections,
PropertyLawAsync, PropertyLawSyntax. PropertyLawMinimalTypes adds none.
```

A protocol's laws live in its own `Public/<Protocol>Laws.swift` file in PropertyLawKit, each law's tier is fixed at its definition, and `KnownProtocol` in PropertyLawCore is the one list the macro and the plugin dispatch on.

-----

## 7. Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Developer frustration from false positives kills adoption | High | Strictness tiers (§4.2) demote conventional/heuristic checks; suppression API (§4.7) provides per-law skip and intentional-violation escape hatches, and every suppression stays visible in the results. |
| Weak generators produce green tests that miss real bugs | High | Derivation is prioritized and visible (§5.7); fallback emits `.todo` stubs that don't compile; the plugin summary buckets `.todo` types by reason; `CheckResult.coverageHints` records actual distribution when a classifier is supplied. |
| Conditional laws pass without testing anything | Medium | Conditional laws report `applications` (§4.6); walks over an `Enumeration` reach rare cases by construction; `equalValuePairing` finds equal values a wide generator rarely pairs (§4.4). |
| Swift macro / plugin diagnostics UX is poor | Medium | Diagnostic quality is a first-class M1 deliverable; trial output includes the strictness tier and a "not a proof" disclaimer. |
| Generated tests are noisy / low signal | Medium | Layered scope (Core / Advisory); Advisory is off by default; suppression markers persist across regeneration. |
| Cross-function pairing is O(n²) at scale | Low | Type-directed filtering; cross-function discovery is Advisory and off by default. |
| Discovery over a large target is slow | Medium | Discovery is an on-demand command plugin, not a build step, so the cost is paid only when someone regenerates. |
| Seed replay across backends or toolchains silently runs a different test | Low | One backend ships; the `Environment` fingerprint and `ReplayEnvironmentMismatch` make a stale seed fail loudly (§4.6). |
| Checkbox testing — green output assumed to mean correctness | Medium | Every output carries an explicit "empirical evidence, not a proof" disclaimer (§4.6). |

-----

## 8. Success Criteria

### PropertyLawKit

- A developer can add protocol law checking for a custom `Equatable` type in under 5 minutes (UX criterion).
- Protocol law violations produce failure messages that identify the specific violated protocol law, its strictness tier, and a reproducible counterexample (replayable seed).
- The package builds and its tests pass on macOS via `swift test`. CI (`.github/workflows/ci.yml`) runs on every push to `main`, every pull request against `main`, and on manual dispatch. It has a macOS test job (`swift test`) and a build matrix that builds the `PropertyLawKit` and `PropertyLawMacro` schemes for iOS, tvOS, watchOS and visionOS with `xcodebuild`, all on `macos-15` runners with the latest stable Xcode. Linux and Windows are not verified. The kit uses no Foundation API beyond what `Codable` already implies, so Linux is *expected* to work, but expected ≠ verified.
- **Framework self-test gate (every CI run).** PropertyLawKit ships a planted-bug suite: types deliberately violating each Strict law, asserted to be detected by the framework. A green CI run requires every planted violation to be caught at the expected strictness tier. This catches regressions in the framework itself — without it, a bug that silences the symmetry check would pass CI undetected.
- **External validation gate (met).** Three artifacts in `Validation/`, each demonstrating one face of the kit's pipeline against external real-world Swift code:

  1. **Pass 1 — discovery scan.** The `propertylawcheck discover` plugin emits law-check scaffolding for **at least four real-world Swift packages** without crashes, malformed output, or false-positive duplicate suites. Generated files plus per-package `.todo` summaries are checked into `Validation/results/`.
  2. **Pass 2 — composition.** The kit composes with at least one external SwiftPM dependency and runs at least one Strict-tier law check end-to-end against a public type from that package, with the test target green under `swift test`.
  3. **Pass 3 — archaeology.** A git-archaeology survey of fix-commits across full-history Swift packages, with results documented in `Validation/FINDINGS.md`. The artifact is the documented search effort and any candidate bugs found — *regardless of whether the kit catches them*. A null result is a valid Pass 3 outcome and counts toward the gate, provided the search method, surveyed corpus, and rejection rationale are all in the repository.

  **Why the gate measures the pipeline rather than retroactive bug discovery.** An earlier version required catching a real bug in 5+ popular packages. Empirically — see `Validation/FINDINGS.md` Pass 3 — that bar is approximately uncloseable: across the full-history Apple/SSWG/community packages surveyed (`swift-argument-parser`, `swift-aws-lambda-runtime`, `swift-collections`, `swift-nio`, `hummingbird`), exactly one candidate fix-commit survived initial filtering, and on inspection the bug was in dead code unreachable through the public API. The structural reasons are clear: well-tested Swift OSS leans on synthesized conformances (bulletproof by construction); hand-written conformances in scrutinized code land correct on first commit and rarely get patched; the population of historical kit-detectable bugs in well-tested packages is approximately empty. The kit's value prop is therefore *prevention* — catching bugs in new code as it's written, before they ship — not retroactive *discovery* in code that's already been hammered by years of users. The gate measures what the kit can actually deliver: pipeline composition (Pass 1+2) plus an honest, documented search effort (Pass 3).

### PropertyLawMacro

- The discovery plugin correctly identifies conformances in a real-world Swift module with less than 5% false-positive High-confidence suggestions in the Advisory layer.
- Generated test stubs for types with derivable generators compile without modification.
- For types where derivation fails, the plugin always emits a non-compiling `.todo` stub — never a silently green test.

-----

## 9. Resolved Decisions

These were Open Questions in v0.1; later revisions committed to a direction.

1. **Naming.** `SwiftPropertyLaws` (package) / `PropertyLawKit` (library) / `PropertyLawMacro` (macros) / `PropertyLawCore` (shared derivation and emission, used by the macro, the plugin and downstream tools). **Single repository, multiple products.** The tooling is too tightly coupled to the PropertyLawKit API for separate-repo versioning to be worth the overhead.
2. **Generator convention.** **Every check takes an explicit `Generator`.** There is no implicit generator at the call site. Derivation lives in the tooling: the macro and the plugin write the derived expression into the generated code, where a reviewer can read it, and when nothing derives they emit a non-compiling `.todo` stub — never silent fallthrough.
3. **Conformance scope.** PropertyLawKit ships the stdlib protocols in §4.3 and the kit-defined protocols in §4.9, audited in-tree. Laws and generators that need a third-party dependency ship as opt-in products (§4.10), so the main library depends on `swift-property-based` alone.
4. **Macro vs. Swift Package Plugin for discovery.** **Both, with clear roles.** Peer macros wire one type at a time, because a macro sees only its decoratee. **Whole-module discovery is a command plugin**, not a macro — macros cannot read other files in the module, and the plugin can read every file in a target and its dependencies.
5. **Relationship to swift-testing.** **Generated code is plain Swift Testing**: a struct of `@Test` methods (the plugin's carries `@Suite`), each calling a check function. Results report through Swift Testing — a thrown `PropertyLawViolation` for escalated violations, a recorded issue for the rest — so the runner's reporting, filtering and parallelization apply unchanged.

Remaining open question, deferred to a future revision:

- **Stateful / model-based testing.** The kit checks invariants and idempotence over sampled action sequences (§4.9), and can walk every sequence up to a length (§4.4), but has no general state-machine layer with commands, preconditions and a model. Whether to add one remains open.

-----

## 10. References

- [swift-property-based](https://github.com/x-sheep/swift-property-based) — primary backend target
- [SwiftQC](https://github.com/Aristide021/SwiftQC) — alternative backend, not adopted
- [SwiftCheck](https://github.com/typelift/SwiftCheck) — prior art, now dormant
- [QuickCheck](https://hackage.haskell.org/package/QuickCheck) and `quickcheck-classes` — Haskell prior art (law libraries are the closest analog to PropertyLawKit)
- [proptest](https://github.com/proptest-rs/proptest) and the `arbitrary` derive — Rust prior art (`arbitrary` is the closest analog to generator derivation)
- [Hedgehog](https://hackage.haskell.org/package/hedgehog) — state-machine testing reference
- [EvoSuite](https://www.evosuite.org) — Java property inference inspiration
- [Daikon](https://plse.cs.washington.edu/daikon/) — runtime invariant inference reference
- Swift Evolution [SE-0185](https://github.com/apple/swift-evolution/blob/main/proposals/0185-synthesize-equatable-hashable.md) — synthesized protocol conformances

-----

## Appendix A: Changelog vs. v0.2

v0.3 is a tightly-scoped revision: one criterion rewritten, one protocol's law set expanded, three minor wording catch-ups. No new milestones, no architectural change.

**Tier 1 — criterion calibration:**

- **§8 Validation criterion rewritten.** v0.2's "catch a real bug in 5+ popular Swift packages before 1.0" is replaced with the **External validation gate**: three documented artifacts in `Validation/` (Pass 1 discovery scan over ≥4 packages, Pass 2 composition with ≥1 external SwiftPM dep, Pass 3 git-archaeology with results in FINDINGS.md). A null Pass 3 outcome is a valid result. See §8 for the full rationale and `Validation/FINDINGS.md` for the empirical evidence that drove the rewrite.

**Tier 2 — coverage expansion:**

- **§4.3 SetAlgebra expanded from five laws to nine.** The four `symmetricDifference*` laws (`symmetricDifferenceSelfIsEmpty`, `symmetricDifferenceEmptyIdentity`, `symmetricDifferenceCommutativity`, `symmetricDifferenceDefinition`) were added in response to the Pass 3 archaeology surfacing a `swift-collections` typo fix in `_Bitmap.symmetricDifference`. The original five-law suite did not exercise the `symmetricDifference` operation at all. All four new laws ship at the Strict tier.

**Tier 3 — wording / scope catch-ups:**

- **§8 framework self-test gate** retained verbatim from v0.2. v0.3 does not change the kit's CI guarantees; it changes only how 1.0-readiness is *measured against external code*.
- **§4.5 / §4.8 / §6 SwiftQC reconciliation.** The "Single-backend by design" decision (commit `74fb9f2`, made between v0.2 and v0.3) dropped the planned SwiftQC second backend; the PRD's M4 row, the §4.5 "Deferred public abstraction" paragraph, and the §6 architecture diagram all still listed SwiftQC as a shipped or imminently-shipping backend. v0.3 reconciles these: the M4 row drops "SwiftQC backend"; §4.5 reframes around "single-backend by design" with SwiftQC's semantics as a design check rather than a planned implementation; §6 replaces the SwiftQC line in the diagram with an "abstraction is public since M4" note. No API or scope change.
- **Appendix A renumbering.** The v0.2 → v0.1 changelog moves to Appendix B. v0.3's changelog (this section) takes the Appendix A slot, so a reader of the latest PRD encounters the most recent calibration first.

**What v0.3 does *not* change:**

- §4.2 Strictness tiers, §4.4 trial budgets, §4.5 backend abstraction, §4.6 confidence reporting, §4.7 suppression, §4.8 milestones — all carry forward unchanged.
- §5.* PropertyLawMacro (Core / Advisory / Experimental layering, derivation priority, plugin-vs-macro split) — unchanged. M4–M6 remain on the roadmap with the same scope they had in v0.2.
- §9 Resolved Decisions — unchanged. The single-backend-by-design decision (made post-v0.2 in `74fb9f2`) was implementation-level rather than scope-level and lives in `CLAUDE.md`'s repo-state notes; it does not require a PRD-level resolution.

-----

## Appendix B: Changelog vs. v0.1

**Tier 1 — consensus changes from external critique (raised by 2+ reviewers):**

- **§4.2 (new)**: Strictness tiers (Strict / Conventional / Heuristic) classify every protocol law and govern default failure behavior.
- **§4.3**: Tier column added to all six protocol law tables; `Codable` round-trip exposes `.strict` / `.semantic(equivalent:)` / `.partial(fields:)` modes.
- **§5.2 (new)**: Layered scope — Core / Advisory / Experimental — with Advisory and Experimental features off by default. Missing-conformance suggestions and cross-function discovery move to Advisory.
- **§5.7**: Generator derivation expanded with explicit priority order, recursive-type handling, override mechanism, and weak-generator telemetry.

**Tier 2 — substantive single-reviewer changes:**

- **§4.5**: `PropertyBackend.check` signature now `@Sendable (T) async throws -> Bool` returning `async throws -> CheckResult`; explicit deferral of the public abstraction surface to M4.
- **§4.4**: Trial budget tiers (`.sanity` / `.standard` / `.thorough` / `.custom`).
- **§4.7 (new)**: Suppression and customization API — per-type, per-law, intentional-violation, custom equivalence.
- **§5.6**: Property contradiction detection reframed as "pattern warnings for known combinations" — curated, not derived; explicitly disclaims soundness.
- **§9 Decision 4**: Whole-module discovery committed to a Swift Package Plugin, not a macro.
- **§9 Decision 5**: `@PropertyLawSuite` implemented as a Swift Testing custom Trait.
- **§8**: Real-world validation criterion added — must catch a real bug in 5+ popular Swift packages before 1.0.

**Tier 3 — strategic / polish:**

- **§1.1 (new)**: "Why Now" section.
- **§1**: Killer-use-case anchor sentence.
- **§2.3**: Explicit positioning vs. Rust `proptest` and Haskell QuickCheck.
- **§4.6**: Sample reports for pass / near-miss / fail outcomes; "not a proof" disclaimer; coverage hints in `CheckResult`.
- **§5.3**: Developer Workflow subsection (regeneration-as-diff, suppression deltas).
- **§6**: Architecture diagram surfaces a named `LawRegistry` layer.
- **§7**: New risks added — adoption-killing false positives; recursive monorepo discovery; pattern-warning misinterpretation; checkbox-testing.
- **§9**: Open Questions become Resolved Decisions with committed directions.
- **§10**: References sharpened to identify each prior art's role (law libraries, `arbitrary` derive, state-machine testing).

**Beyond the external critiques — own design pass:**

Items the three external critiques did not raise but which v0.2 also addresses, identified during a follow-up review:

- **§4.3 inheritance semantics.** `checkXxxPropertyLaws` runs the inherited suites by default (`checkHashable` runs Equatable's laws; `checkComparable` runs Equatable's; `checkCollection` runs Sequence's and IteratorProtocol's). `.ownOnly` is the opt-out. Property tests are too expensive to make "remember to chain" the user's responsibility, and forgetting to chain is a silent way to miss real semantic bugs. The Discovery plugin emits the most specific call per type, so generated tests don't double-run inherited laws.
- **§4.3 IteratorProtocol and Sequence laws.** Added; v0.1 had `Collection` without its dependencies. The §4.3 Coverage Scope subsection now enumerates what's in v1, what's a v1.1 candidate, what's heuristic/deferred, and what's permanently out of scope (cross-referenced against `docs/Protocols/Swift Standard Library Protocols.md`).
- **§4.3 `Codable.partial(fields:)` typed as `[PartialKeyPath<T>]`** rather than `[String]` — type-safe, refactor-safe.
- **§4.4 Generic Conformances.** Conditional / generic conformances are checked by binding type parameters at the call site; the Discovery plugin requires explicit `@LawGenerator(bindings: ...)` rather than enumerating the unbounded space.
- **§4.5 Actor-Isolated and Sendable Types.** Spelled out: actor hop per trial, Sendable closures, registry implemented as an actor for Swift 6 concurrency safety. Sendable's value-semantics contract is explicitly named as a deferred research item.
- **§4.6 near-miss semantics defined.** Per-protocol criterion table, plus `nearMisses: nil` to distinguish "no near-misses" from "backend doesn't track them."
- **§4.6 environment fingerprint on `CheckResult`.** Replay verifies Swift version, backend version, and generator-schema hash; a stale seed fails loudly instead of silently replaying a different test.
- **§8 framework self-test gate.** Planted-bug suite asserts the framework itself catches every Strict violation on every CI run — guards against regressions in the law-checker.
