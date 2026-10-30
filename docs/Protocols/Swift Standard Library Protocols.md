# Swift Standard Library Protocols

A comprehensive reference of all ~78 public protocols in the Swift Standard Library, grouped by category.

-----

## 1. Equality & Comparison

### `Equatable`

- **Requirement:** `static func == (lhs: Self, rhs: Self) -> Bool`
- Types that can be compared for equality. Enables use of `==` and `!=`.

### `Comparable`

- **Inherits:** `Equatable`
- **Requirement:** `static func < (lhs: Self, rhs: Self) -> Bool`
- Types that have a natural ordering. Enables `<`, `>`, `<=`, `>=` and use in `sorted()`.

### `Hashable`

- **Inherits:** `Equatable`
- **Requirement:** `func hash(into hasher: inout Hasher)`
- Types that can be hashed to an integer. Required to be used as `Dictionary` keys or in `Set`.

### `Identifiable`

- **Requirement:** `var id: ID { get }` (where `ID: Hashable`)
- Types with a stable identity. Widely used in SwiftUI `List` and `ForEach`.

-----

## 2. Collections

### `Sequence`

- **Requirement:** `func makeIterator() -> Self.Iterator`
- The most basic protocol for anything you can loop over with `for...in`.

### `IteratorProtocol`

- **Requirement:** `mutating func next() -> Element?`
- Provides values one at a time. Returned by `Sequence.makeIterator()`.

### `AsyncSequence`

- **Requirement:** `func makeAsyncIterator() -> Self.AsyncIterator`
- The asynchronous counterpart of `Sequence`, looped over with `for await...in` or `for try await...in`. Declared in `_Concurrency`, which every Swift file imports implicitly.

### `AsyncIteratorProtocol`

- **Requirement:** `mutating func next() async throws -> Element?`
- Provides values one at a time, asynchronously. Returned by `AsyncSequence.makeAsyncIterator()`. Also declared in `_Concurrency`.

### `Collection`

- **Inherits:** `Sequence`
- **Requirements:** `var startIndex: Index`, `var endIndex: Index`, `subscript(position: Index) -> Element`, `func index(after i: Index) -> Index`
- A sequence you can traverse multiple times with subscript access.

### `BidirectionalCollection`

- **Inherits:** `Collection`
- **Requirement:** `func index(before i: Index) -> Index`
- A collection that can be traversed both forward and backward.

### `RandomAccessCollection`

- **Inherits:** `BidirectionalCollection`
- **Requirement:** O(1) index manipulation (no explicit method beyond `BidirectionalCollection`)
- A collection with efficient random access (like arrays).

### `MutableCollection`

- **Inherits:** `Collection`
- **Requirement:** `subscript(position: Index) -> Element { get set }`
- A collection whose elements can be modified in place.

### `RangeReplaceableCollection`

- **Inherits:** `Collection`
- **Requirements:** `init()`, `mutating func replaceSubrange(_ subrange: Range<Index>, with newElements: C)`
- A collection that supports inserting and removing elements.

### `StringProtocol`

- **Inherits:** `BidirectionalCollection`, `Hashable`, `Comparable`, `LosslessStringConvertible`, `ExpressibleByStringInterpolation`, `TextOutputStream`, `TextOutputStreamable`
- **Key properties:** `var utf8: UTF8View`, `var utf16: UTF16View`, `var unicodeScalars: UnicodeScalarView`
- Shared interface for `String` and `Substring`.

### `LazySequenceProtocol`

- **Inherits:** `Sequence`
- **Requirement:** `var elements: Elements { get }`
- A sequence that applies transformations lazily (on demand).

### `LazyCollectionProtocol`

- **Inherits:** `LazySequenceProtocol`, `Collection`
- The collection counterpart to `LazySequenceProtocol`.

### `SetAlgebra`

- **Inherits:** `Equatable`, `ExpressibleByArrayLiteral`
- **Requirements:** `init()`, `func contains(_ member: Element) -> Bool`, `func union(_ other: Self) -> Self`, `func intersection(_ other: Self) -> Self`, `func symmetricDifference(_ other: Self) -> Self`, `mutating func formUnion(_ other: Self)`, `mutating func formIntersection(_ other: Self)`, `mutating func formSymmetricDifference(_ other: Self)`, `mutating func insert(_ newMember: Element) -> (inserted: Bool, memberAfterInsert: Element)`, `mutating func remove(_ member: Element) -> Element?`, `mutating func update(with newMember: Element) -> Element?`. Also required, with default implementations: `func subtracting(_ other: Self) -> Self`, `mutating func subtract(_ other: Self)`, `func isSubset(of other: Self) -> Bool`, `func isSuperset(of other: Self) -> Bool`, `func isDisjoint(with other: Self) -> Bool`, `var isEmpty: Bool`, `init<S: Sequence>(_ sequence: S)`.
- A type representing a mathematical set, with union, intersection, and symmetric-difference operations. Adopters: `Set`, `OptionSet` types, `IndexSet`, `CharacterSet`, plus swift-collections' `TreeSet`, `BitSet` and `OrderedSet.UnorderedView` (`OrderedSet` itself does not conform). Note: SetAlgebra is filed under Apple's "Collections" documentation topic but does *not* inherit from `Collection` — `Set` adopts both protocols separately. For the laws PropertyLawKit checks, see PRD §4.3 SetAlgebra.

### `OptionSet`

- **Inherits:** `RawRepresentable`, `SetAlgebra`
- **Requirement:** `init(rawValue: RawValue)`
- A set of flags stored as bits of a raw value, where each element is itself an `OptionSet` value.

### `RangeExpression`

- **Requirements:** `associatedtype Bound: Comparable`, `func relative<C: Collection>(to collection: C) -> Range<Bound>`, `func contains(_ element: Bound) -> Bool`
- A type that can describe a range of a collection's indices. Adopted by `Range`, `ClosedRange` and the partial ranges (`..<n`, `...n`, `n...`).

-----

## 3. Numeric Protocols

### `Numeric`

- **Inherits:** `AdditiveArithmetic`, `ExpressibleByIntegerLiteral`
- **Requirements:** `*`, `*=`, `init?(exactly:)`, `var magnitude: Magnitude` (`+` and `-` come from `AdditiveArithmetic`)
- Base protocol for all numeric types that support multiplication.

### `SignedNumeric`

- **Inherits:** `Numeric`
- **Requirement:** `mutating func negate()`
- Numeric types that can be negative.

### `AdditiveArithmetic`

- **Inherits:** `Equatable`
- **Requirements:** `static var zero: Self`, `+`, `-`
- Types supporting addition and subtraction.

### `BinaryInteger`

- **Inherits:** `Numeric`, `Hashable`, `CustomStringConvertible`, `Strideable`
- **Requirements:** `init<T: BinaryInteger>(_ source: T)`, bitwise operators (`&`, `|`, `^`, `~`, `<<`, `>>`)
- Base protocol for all integer types (`Int`, `UInt`, etc.).

### `SignedInteger`

- **Inherits:** `BinaryInteger`, `SignedNumeric`
- Signed integer types (`Int`, `Int8`, `Int16`, `Int32`, `Int64`).

### `UnsignedInteger`

- **Inherits:** `BinaryInteger`
- Unsigned integer types (`UInt`, `UInt8`, `UInt16`, `UInt32`, `UInt64`).

### `FixedWidthInteger`

- **Inherits:** `BinaryInteger`, `LosslessStringConvertible`
- **Key properties/requirements:** `static var bitWidth: Int`, `static var max: Self`, `static var min: Self`, overflow operators (`&+`, `&-`, `&*`), `nonzeroBitCount`, `leadingZeroBitCount`
- Integer types with a fixed bit width.

### `FloatingPoint`

- **Inherits:** `SignedNumeric`, `Strideable`, `Hashable`
- **Key properties:** `var isNaN: Bool`, `var isInfinite: Bool`, `var isFinite: Bool`, `var isZero: Bool`, `var sign: FloatingPointSign`, `var exponent: Exponent`, `var significand: Self`
- **Key requirements:** `static var infinity: Self`, `static var nan: Self`, `static var pi: Self`, `func squareRoot() -> Self`, `mutating func round(_ rule: FloatingPointRoundingRule)`
- Base for all floating-point types.

### `BinaryFloatingPoint`

- **Inherits:** `FloatingPoint`, `ExpressibleByFloatLiteral`
- **Requirements:** `static var exponentBitCount: Int`, `static var significandBitCount: Int`
- Floating-point types using binary encoding (`Float`, `Double`, `Float80`).

### `Strideable`

- **Inherits:** `Comparable`
- **Requirements:** `func distance(to other: Self) -> Stride`, `func advanced(by n: Stride) -> Self`
- Types that can be stepped through in a `for` loop with `stride(from:to:by:)`.

### `SIMD`

- **Inherits:** `SIMDStorage`, `Hashable`, `Encodable`, `Decodable`, `CustomStringConvertible`, `ExpressibleByArrayLiteral`
- A fixed-width vector of `Scalar` values with lane-wise operations. Adopted by `SIMD2` through `SIMD64`.

### `SIMDStorage`

- **Requirements:** `var scalarCount: Int`, `init()`, `subscript(index: Int) -> Scalar { get set }`
- The storage beneath a `SIMD` vector: a fixed number of scalars addressed by index.

### `SIMDScalar`

- **Inherits:** `BitwiseCopyable`
- Types that can be SIMD lanes. Supplies the storage type for each vector width (`SIMD2Storage` … `SIMD64Storage`) and a mask scalar type. Adopted by the integer types up to 64 bits, `Float16`, `Float` and `Double`.

-----

## 4. Encoding & Decoding

### `Encodable`

- **Requirement:** `func encode(to encoder: Encoder) throws`
- Types that can encode themselves (e.g., to JSON).

### `Decodable`

- **Requirement:** `init(from decoder: Decoder) throws`
- Types that can decode themselves from external data.

### `Codable`

- **Inherits:** `Encodable`, `Decodable`
- Typealias combining both. The standard way to support JSON/Plist serialization.

### `Encoder`

- **Key requirements:** `var codingPath: [CodingKey]`, `var userInfo: [CodingUserInfoKey: Any]`, container methods (`container(keyedBy:)`, `unkeyedContainer()`, `singleValueContainer()`)

### `Decoder`

- **Key requirements:** `var codingPath: [CodingKey]`, `var userInfo: [CodingUserInfoKey: Any]`, container methods

### `CodingKey`

- **Inherits:** `CustomStringConvertible`, `CustomDebugStringConvertible`, `Sendable`
- **Requirements:** `var stringValue: String`, `var intValue: Int?`, `init?(stringValue:)`, `init?(intValue:)`
- Keys used in encoding/decoding keyed containers.

### `CodingKeyRepresentable`

- **Requirements:** `var codingKey: CodingKey { get }`, `init?<T: CodingKey>(codingKey: T)`
- Lets a type other than `String` or `Int` key a `Dictionary` that encodes as a keyed container rather than as an array of key/value pairs.

### Coding containers

The containers an `Encoder` or `Decoder` hands out. A custom encoder or decoder implements them.

|Protocol                        |Role                                                         |
|--------------------------------|-------------------------------------------------------------|
|`KeyedEncodingContainerProtocol`|Encodes values under `CodingKey`s (wrapped by `KeyedEncodingContainer`)|
|`UnkeyedEncodingContainer`      |Encodes an ordered sequence of values                        |
|`SingleValueEncodingContainer`  |Encodes a single value                                       |
|`KeyedDecodingContainerProtocol`|Decodes values by `CodingKey` (wrapped by `KeyedDecodingContainer`)|
|`UnkeyedDecodingContainer`      |Decodes an ordered sequence of values                        |
|`SingleValueDecodingContainer`  |Decodes a single value                                       |

-----

## 5. String Representation

### `CustomStringConvertible`

- **Requirement:** `var description: String { get }`
- Provides a human-readable string via `String(describing:)` and print.

### `CustomDebugStringConvertible`

- **Requirement:** `var debugDescription: String { get }`
- Provides a debug-friendly string via `String(reflecting:)`.

### `LosslessStringConvertible`

- **Inherits:** `CustomStringConvertible`
- **Requirement:** `init?(_ description: String)`
- Types that can be round-tripped through a string without information loss.

### `TextOutputStreamable`

- **Requirement:** `func write<Target: TextOutputStream>(to target: inout Target)`
- Types that can write themselves to a text stream.

### `TextOutputStream`

- **Requirement:** `mutating func write(_ string: String)`
- A type that accepts strings written to it (e.g., a custom output buffer).

### `StringInterpolationProtocol`

- **Requirements:** `init(literalCapacity: Int, interpolationCount: Int)`, `mutating func appendLiteral(_ literal: StringLiteralType)`
- The builder an `ExpressibleByStringInterpolation` type uses to assemble `"…\(value)…"`. Each `appendInterpolation` method it declares adds an interpolation form. The default is `DefaultStringInterpolation`.

### `UnicodeCodec`

- **Requirements:** `init()`, `mutating func decode<I: IteratorProtocol>(_ input: inout I) -> UnicodeDecodingResult`, `static func encode(_ input: Unicode.Scalar, into processCodeUnit: (CodeUnit) -> Void)`
- A Unicode encoding scheme that translates between code units and scalars. Adopted by `Unicode.UTF8`, `Unicode.UTF16` and `Unicode.UTF32`.

-----

## 6. Raw Value Representation

### `RawRepresentable`

- **Requirements:** `associatedtype RawValue`, `var rawValue: RawValue { get }`, `init?(rawValue: RawValue)`
- Types (especially enums) that have an underlying raw value representation.

-----

## 7. Memory & Reference

### `AnyObject`

- Protocol to which all class types implicitly conform.
- Used to constrain generics to reference (class) types.
- `AnyClass` is not a protocol: it is a typealias for `AnyObject.Type`, the metatype of any class.

### `Sendable`

- **Inherits:** `SendableMetatype`
- Marks types that are safe to use in concurrent code (across actor boundaries). No required methods.

### `SendableMetatype`

- Marks types whose metatype (`T.Type`) can cross concurrency domains. `Sendable` refines it. No required methods.

### `Copyable`

- Marker protocol every type conforms to by default: its values can be copied. Suppressed with `~Copyable` to declare a noncopyable type.

### `Escapable`

- Marker protocol every type conforms to by default: its values can outlive the scope that produced them. Suppressed with `~Escapable` for types like `Span`.

### `BitwiseCopyable`

- Marker protocol for types whose values can be copied with a plain memory copy, with no retain, release or other copy work. No required methods.

### `Error`

- **Inherits:** `Sendable`
- **Requirement:** None required (beyond conformance)
- Types that can be thrown and caught as errors. Foundation's `LocalizedError` (not a stdlib protocol) refines it with optional `errorDescription`, `failureReason`, `recoverySuggestion` and `helpAnchor` properties.

-----

## 8. Literals (ExpressibleBy…)

These protocols let custom types be initialized from literal syntax.

|Protocol                                     |Requirement                            |Literal Type         |
|---------------------------------------------|---------------------------------------|---------------------|
|`ExpressibleByIntegerLiteral`                |`init(integerLiteral:)`                |`42`                 |
|`ExpressibleByFloatLiteral`                  |`init(floatLiteral:)`                  |`3.14`               |
|`ExpressibleByBooleanLiteral`                |`init(booleanLiteral:)`                |`true`               |
|`ExpressibleByStringLiteral`                 |`init(stringLiteral:)`                 |`"hello"`            |
|`ExpressibleByStringInterpolation`           |`init(stringInterpolation:)`           |`"Hello, \(name)"`   |
|`ExpressibleByNilLiteral`                    |`init(nilLiteral:)`                    |`nil`                |
|`ExpressibleByArrayLiteral`                  |`init(arrayLiteral:)`                  |`[1, 2, 3]`          |
|`ExpressibleByDictionaryLiteral`             |`init(dictionaryLiteral:)`             |`["a": 1]`           |
|`ExpressibleByUnicodeScalarLiteral`          |`init(unicodeScalarLiteral:)`          |single Unicode scalar|
|`ExpressibleByExtendedGraphemeClusterLiteral`|`init(extendedGraphemeClusterLiteral:)`|single character     |

-----

## 9. Miscellaneous

### `CustomReflectable`

- **Requirement:** `var customMirror: Mirror { get }`
- Types that provide a custom reflection (used by `Mirror` for introspection).

### `CustomLeafReflectable`

- **Inherits:** `CustomReflectable`
- A `CustomReflectable` type that is reflected as a leaf: its mirror stands alone, without any superclass representation.

### `CustomPlaygroundDisplayConvertible`

- **Requirement:** `var playgroundDescription: Any { get }`
- Supplies the value an Xcode playground displays in place of the instance.

### `MirrorPath`

- Identifies a particular stored property in a `Mirror` via string or integer subscripts.

### `Hashable` *(see Equality section)*

### `CVarArg`

- Types that can be passed as C variadic arguments. No user-facing requirements.

### `RandomNumberGenerator`

- **Requirement:** `mutating func next() -> UInt64`
- Custom random number generators used with `random(in:using:)` APIs.

### `CaseIterable`

- **Requirement:** `static var allCases: AllCases { get }` (where `AllCases: Collection` with `Self` elements; `[Self]` by default)
- Types with a finite list of every value, usually enums without associated values, for which the compiler synthesizes `allCases`.

### `InstantProtocol`

- **Inherits:** `Comparable`, `Hashable`, `Sendable`
- **Requirements:** `func advanced(by duration: Duration) -> Self`, `func duration(to other: Self) -> Duration`
- A point in time, such as `ContinuousClock.Instant`. The `Clock` protocol that produces instants is declared in `_Concurrency`.

### `DurationProtocol`

- **Inherits:** `AdditiveArithmetic`, `Comparable`, `Sendable`
- **Requirements:** `*` and `/` by an `Int` (plus `*=` and `/=`), `static func / (lhs: Self, rhs: Self) -> Double`
- An elapsed time between two instants. The stdlib's concrete type is `Duration`.

-----

## Summary by Category

|Category                 |Count  |
|-------------------------|-------|
|Equality & Comparison    |4      |
|Collections              |15     |
|Numeric                  |13     |
|Encoding & Decoding      |12     |
|String Representation    |7      |
|Raw Value Representation |1      |
|Memory & Reference       |7      |
|Literals (ExpressibleBy…)|10     |
|Miscellaneous            |9      |
|**Total**                |**~78**|

`Codable` is a typealias for `Decodable & Encodable` and is not counted.

-----

*Based on the Swift Standard Library as of Swift 6.3, plus `AsyncSequence` and `AsyncIteratorProtocol` from the implicitly imported `_Concurrency` module. Left out: underscored protocols, the deprecated `UnsafeSendable`, and `_Concurrency`'s actor, executor and clock protocols. Swift 6.4 adds `BorrowingIteratorProtocol`, `Iterable`, `ConvertibleToBytes` and `ConvertibleFromBytes`, which are not listed here. The exact count can vary slightly across Swift versions as protocols are added, renamed, or deprecated.*

-----

## Kit-defined Protocols

PropertyLawKit also defines protocols of its own where the Swift Standard Library leaves a gap: the algebraic `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice` and `Ring`; the `InteractionInvariant` family; and `ValueSemantic`, `StableIdentity` and `DefensiveCopy`. They are not stdlib protocols and are not counted above. Their requirements, laws and status are in the "Kit-defined protocols" section of the [SwiftPropertyLaws PRD](SwiftPropertyLaws%20PRD.md).