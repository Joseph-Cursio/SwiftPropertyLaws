# SwiftPropertyLaws

Property-based protocol law checks for Swift's standard-library protocols. Catches semantic conformance bugs the compiler can't.

> This is an experiment in property-based testing. I selected Swift's protocols to start because many have clearly identifiable properties. 

> **Status:** v1.3.0 released — PRD §5.7 Strategy 3 memberwise-Arbitrary generator derivation shipped on top of v1.2's collection-refinements cluster and v1.1's round-trip cluster. 308 tests passing on Swift 6.3, macOS 14+. See [Status](#status) for what's stable.

## The problem

Swift's compiler enforces the *structural* contract of a protocol — methods exist with correct signatures. It does not and cannot enforce the *behavioral* contract. All three of these compile cleanly:

```swift
// Violates Equatable.symmetry: x == y differs from y == x
extension MyType: Equatable {
    static func == (lhs: MyType, rhs: MyType) -> Bool {
        return lhs.priority > rhs.priority
    }
}

// Violates Hashable: equal values produce different hashes
extension MyType: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(UUID())  // breaks Dictionary, Set
    }
}

// Violates Codable round-trip fidelity
extension MyType: Codable {
    // encode omits a field; decode provides a default
    // decode(encode(x)) ≠ x for non-default values
}
```

Each is a real production bug class. None is caught by `swift build`.

## What it covers

| Protocol | Laws |
|---|---|
| `Equatable` | reflexivity, symmetry, transitivity, negation consistency |
| `Hashable` | hash/equality consistency, stability within a process, distribution |
| `Comparable` | antisymmetry, transitivity, totality, operator consistency |
| `Strideable` | distance round-trip, advance round-trip, zero-advance identity, self-distance is zero |
| `Codable` | round-trip fidelity (`.strict` / `.semantic` / `.partial` modes) |
| `RawRepresentable` | `T(rawValue: x.rawValue) == x` round-trip |
| `LosslessStringConvertible` | `T(String(describing: x)) == x` round-trip |
| `Identifiable` | id stability within a process |
| `CaseIterable` | exactly-once enumeration |
| `IteratorProtocol` | termination stability, single-pass yield |
| `Sequence` | `underestimatedCount` lower bound, multi-pass consistency, `makeIterator()` independence |
| `Collection` | count consistency, index validity, non-mutation |
| `BidirectionalCollection` | `index(before:)`/`index(after:)` round-trips both ways, reverse-traversal consistency |
| `RandomAccessCollection` | distance consistency, offset consistency, negative-offset inversion |
| `MutableCollection` | `swapAt` swaps values, `swapAt` involution |
| `RangeReplaceableCollection` | empty-init is empty, remove-at/insert round-trip, `removeAll()` makes empty, `replaceSubrange` applies edit |
| `SetAlgebra` | union/intersection idempotence + commutativity, empty identity |
| `AdditiveArithmetic` | addition associativity + commutativity, zero identity, subtraction inverse, self-subtraction is zero |
| `Numeric` | multiplication associativity + commutativity, multiplicative identity, zero annihilation, left/right distributivity |
| `SignedNumeric` | negation involution, additive inverse, negation distributes over addition, negate-mutation consistency |
| `BinaryInteger` | division/multiplication round-trip, remainder bound, self/by-one division, quotient-remainder consistency, bitwise AND/OR/XOR idempotence + commutativity + identity, double-negation, AND distributes over OR, De Morgan, shift-by-zero identity, trailing-zero bit count range |
| `SignedInteger` | signum consistency |
| `UnsignedInteger` | non-negative, magnitude is self |
| `FixedWidthInteger` | bit-width matches type, four reportingOverflow consistency laws, wrapping arithmetic does not trap, min/max bounds reachable, byteSwapped involution, nonzero bit count range |
| `FloatingPoint` | infinity is infinite, signed-zero equality, additive inverse on finite, next-up/down round-trip, sign matches less-than-zero, absolute value non-negative, plus 5 NaN-domain laws gated by `LawCheckOptions.allowNaN` |
| `BinaryFloatingPoint` | radix-2 constraint, significand/exponent reconstruction, binade membership, integer-conversion exactness |
| `StringProtocol` | String-init round-trip, count match across String conversion, isEmpty / count-zero consistency, hasPrefix / hasSuffix empty, lowercased / uppercased idempotence, UTF-8 view invariance |

Inheritance is implicit: `checkComparable…` runs Equatable's laws automatically, `checkStrideable…` runs Comparable's (and transitively Equatable's), `checkCollection…` runs Sequence's and IteratorProtocol's, `checkRandomAccessCollection…` runs the whole `BidirectionalCollection → Collection → Sequence → IteratorProtocol` chain, and the algebraic chain `checkSignedNumeric…` → `checkNumeric…` → `checkAdditiveArithmetic…` runs in linear order. PRD §4.3 is the spec.

## Installation

```swift
// Package.swift
.package(url: "https://github.com/Joseph-Cursio/SwiftPropertyLaws.git", from: "1.0.0")
```

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
        // Optional — for the @PropertyLawSuite macro:
        .product(name: "PropertyLawMacro", package: "SwiftPropertyLaws"),
    ]
),
```

Requires Swift 6.1+ tools, macOS 14+ at runtime.

## Three ways to use it

### 1. Manual call

The simplest entry point — pass a generator, get back per-law `CheckResult`s.

```swift
import Testing
import PropertyBased
import PropertyLawKit

@Test func myTypeLaws() async throws {
    try await checkHashablePropertyLaws(
        for: MyType.self,
        using: Gen.myType()
    )
}
```

Throws `PropertyLawViolation` on Strict-tier failures with a replayable seed and counterexample.

### 2. `@PropertyLawSuite` peer macro

Apply to a type. The macro reads the type's inheritance clause and emits a peer test struct with one `@Test func` per recognized stdlib conformance.

```swift
import PropertyLawMacro

@PropertyLawSuite
struct MyType: Equatable, Hashable, Codable {
    let id: Int
    let name: String
}

extension MyType {
    static func gen() -> Generator<MyType, some SendableSequenceType> {
        zip(Gen<Int>.int(in: 0...100), Gen<Character>.letterOrNumber.string(of: 1...8))
            .map { MyType(id: $0, name: $1) }
    }
}
```

Expands at compile time to:

```swift
struct MyTypePropertyLawTests {
    @Test func hashable_MyType() async throws { /* ... */ }
    @Test func codable_MyType() async throws { /* ... */ }
}
```

Most-specific-conformance dedupe runs at expansion time — `Hashable` subsumes `Equatable`, etc., so you get one call per protocol.

**Generator derivation (M3).** For `CaseIterable` enums and `RawRepresentable` enums backed by recognized stdlib raw types, the macro derives the generator automatically — no `gen()` method required.

```swift
@PropertyLawSuite
enum Status: CaseIterable, Equatable {
    case pending, active, archived
}
// Macro emits: using: Gen<Status>.element(of: Status.allCases)

@PropertyLawSuite
enum Direction: String, Codable, Equatable {
    case north, south, east, west
}
// Macro emits: using: Gen<Character>.letterOrNumber.string(of: 0...8)
//                       .compactMap { Direction(rawValue: $0) }
```

For other types, the macro falls through to `<TypeName>.gen()` (define it yourself) and warns at compile time explaining what's needed. Memberwise-`Arbitrary` derivation for plain structs is on the roadmap but not in M3.

### 3. Whole-module discovery (Swift Package Plugin)

For projects with many types, run the plugin and commit the generated file.

```bash
swift package --allow-writing-to-package-directory propertylawcheck discover --target MyModule
```

Walks every `.swift` file in the target, aggregates type declarations and extensions across files, and emits `Tests/MyModuleTests/PropertyLawTests.generated.swift` with one `@Suite struct` per recognized type.

Idempotent: re-running with no source changes produces byte-identical output. Suppression markers in the generated file (`// property-law-suppress: <protocol>_<TypeName>`) survive regeneration — the user marks a check as deliberately skipped, the next run keeps it skipped.

## Strictness tiers

Not every law is universally true in idiomatic Swift. `Hashable` allows hash collisions; `Comparable` on `Float`/`Double` fails for `NaN`; `Codable` round-trips are intentionally lossy in many real schemas. The kit classifies every law:

| Tier | Default behavior on violation |
|---|---|
| **Strict** | Test fails. Reflexivity, symmetry, transitivity, count consistency, etc. |
| **Conventional** | Reported as failed, but doesn't throw under `EnforcementMode.default`. Pass `.strict` to escalate. |
| **Heuristic** | Informational only. Never fails. Distribution sanity, etc. |

PRD §4.2 has the full tier-per-law table.

## Suppressions

When a law-check legitimately doesn't apply (`NaN` reflexivity on a `Float`-bearing type, intentional Codable lossiness, etc.) suppress at the call site:

```swift
try await checkEquatablePropertyLaws(
    for: MyType.self,
    using: Gen.myType(),
    options: LawCheckOptions(
        suppressions: [
            .skip(.equatable(.reflexivity), reason: "NaN by design")
        ]
    )
)
```

Two kinds:

- `.skip` — don't run the check; record `.suppressed(reason:)` in the result with `trials: 0`.
- `.intentionalViolation` — run the check; if it would fail, record `.expectedViolation(reason:counterexample:)` instead of `.failed`.

Suppressions never throw, regardless of `EnforcementMode`. They appear in the test report so reviewers see policy drift.

## Confidence reporting

`CheckResult` carries replayable provenance: seed, environment fingerprint (Swift version + backend identity), trial count, near-miss list (when applicable), coverage hints (opt-in via `CoverageClassifier`).

Replay-validation is opt-in: pass an `expectedReplayEnvironment` and the kit refuses to run if the live environment diverges, so a CI artifact stored months earlier doesn't silently re-roll a different test under the same seed string.

## Status

| Component | Status |
|---|---|
| `PropertyLawKit` (PRD Contribution 1) | v1.0 base + v1.1 round-trip + v1.2 collection-refinements + v1.4 numeric/integer/FloatingPoint + v1.5 StringProtocol shipped — closes out the entire PRD §4.3 v1.1+ candidates list |
| `PropertyLawMacro` peer macro (PRD §5.3 Macro Mode) | M1 shipped |
| `swift package propertylawcheck` discovery plugin (PRD §5.3 Discovery Mode) | M2 shipped |
| Generator derivation (PRD §5.7) — `CaseIterable` + `RawRepresentable` enums | M3 shipped |
| Memberwise-`Arbitrary` derivation (PRD §5.7 Strategy 3) | Shipped — structs whose every stored property is a recognized stdlib raw type (Int / String / Bool / Double / Float and the fixed-width integer family) get `zip(...).map { Type(prop: $0.N, …) }` derived through the synthesized memberwise initializer; arity 1–10 (`swift-property-based`'s `zip` overload cap); falls through to `.todo` for non-raw member types, structs declaring user `init`, and class/actor kinds |
| Advisory: missing-conformance suggestions (PRD §5.4) | M4 shipped — opt-in via `--advisory`, HIGH-confidence detectors for `Equatable`, `Hashable`, `Comparable`, `Codable` |
| Advisory: cross-function round-trip discovery (PRD §5.5) | M5 shipped — opt-in via `--advisory`, syntactic pair detector matching curated naming pairs (encode/decode, serialize/deserialize, push/pop, etc.) and signature inversion across same-type member functions + module-level free functions; `@Discoverable(group:)` peer macro promotes group-tagged pairs to HIGH confidence even without a curated naming match |
| Experimental layer (pattern warnings, Codable-derived generators) | Not started |
| 1.0 External validation gate (PRD v0.3 §8 — three-pass) | All three passes shipped: Pass 1 (discovery scan ≥4 packages), Pass 2 (composition with `swift-argument-parser`), Pass 3 (git-archaeology, results in `Validation/FINDINGS.md`) |

The PropertyBackend abstraction (PRD §4.5) is shipped public with `SwiftPropertyBasedBackend` as the single implementation. `swift-property-based` is the only backend v1 ships; the abstraction stays open for future alternatives but the kit doesn't chase parity for its own sake.

## Documentation

- **[`docs/Protocols/SwiftPropertyLaws PRD.md`](docs/Protocols/SwiftPropertyLaws%20PRD.md)** — design specification, the load-bearing reference for what the kit does and why.
- **[`docs/Protocols/Swift Standard Library Protocols.md`](docs/Protocols/Swift%20Standard%20Library%20Protocols.md)** — structural inventory of all ~54 stdlib protocols (Inherits / Requirements / one-liner). Laws and v1/v1.1/deferred classification live in PRD §4.3 and §4.3 Coverage Scope.
- **[`docs/SwiftInferProperties PRD.md`](docs/SwiftInferProperties%20PRD.md)** — design for the downstream SwiftInferProperties package (signature-pattern matcher + test lifter).
- **[`CLAUDE.md`](CLAUDE.md)** — repository state, design decisions baked into the current PRD, build instructions.

## Build & test

```bash
swift package clean && swift test
swiftlint lint
```

Both should be silent on a clean checkout.

## License

MIT — see [LICENSE](LICENSE).
