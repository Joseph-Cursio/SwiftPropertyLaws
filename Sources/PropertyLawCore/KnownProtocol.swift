/// Recognized stdlib protocols that PropertyLawKit covers (PRD §4.3 v1
/// scope). The macro and the discovery plugin both emit
/// `checkXxxPropertyLaws` calls only for these.
///
/// `package`-visibility because both `PropertyLawMacroImpl` and
/// `PropertyLawDiscoveryTool` consume this enum and they need a shared source
/// of truth — but it's an implementation detail, not a public API of the
/// shipped libraries.
package enum KnownProtocol: String, CaseIterable, Hashable, Sendable {
    case equatable
    case hashable
    case comparable
    case codable
    case iteratorProtocol
    case sequence
    case collection
    case bidirectionalCollection
    case randomAccessCollection
    case mutableCollection
    case rangeReplaceableCollection
    case setAlgebra
    case strideable
    case rawRepresentable
    case losslessStringConvertible
    case identifiable
    case caseIterable
    case additiveArithmetic
    case numeric
    case signedNumeric
    case binaryInteger
    case signedInteger
    case unsignedInteger
    case fixedWidthInteger
    case floatingPoint
    case binaryFloatingPoint
    case stringProtocol
    case semigroup
    case monoid
    case commutativeMonoid
    case group
    case semilattice
    case ring

    /// Maps a single inheritance-clause type name to a `KnownProtocol`.
    /// `Encodable`/`Decodable` are intentionally absent — only the pair
    /// resolves to `.codable`, handled by `KnownProtocol.set(from:)`.
    package static func from(typeName: String) -> KnownProtocol? {
        typeNameMap[typeName]
    }

    private static let typeNameMap: [String: KnownProtocol] = [
        "Equatable": .equatable,
        "Hashable": .hashable,
        "Comparable": .comparable,
        "Codable": .codable,
        "IteratorProtocol": .iteratorProtocol,
        "Sequence": .sequence,
        "Collection": .collection,
        "BidirectionalCollection": .bidirectionalCollection,
        "RandomAccessCollection": .randomAccessCollection,
        "MutableCollection": .mutableCollection,
        "RangeReplaceableCollection": .rangeReplaceableCollection,
        "SetAlgebra": .setAlgebra,
        "Strideable": .strideable,
        "RawRepresentable": .rawRepresentable,
        "LosslessStringConvertible": .losslessStringConvertible,
        "Identifiable": .identifiable,
        "CaseIterable": .caseIterable,
        "AdditiveArithmetic": .additiveArithmetic,
        "Numeric": .numeric,
        "SignedNumeric": .signedNumeric,
        "BinaryInteger": .binaryInteger,
        "SignedInteger": .signedInteger,
        "UnsignedInteger": .unsignedInteger,
        "FixedWidthInteger": .fixedWidthInteger,
        "FloatingPoint": .floatingPoint,
        "BinaryFloatingPoint": .binaryFloatingPoint,
        "StringProtocol": .stringProtocol,
        "Semigroup": .semigroup,
        "Monoid": .monoid,
        "CommutativeMonoid": .commutativeMonoid,
        "Group": .group,
        "Semilattice": .semilattice,
        "Ring": .ring
    ]

    /// Resolve a list of raw inherited-type names into the recognized
    /// `KnownProtocol` set, including the `Encodable + Decodable` →
    /// `.codable` pairing and the `Strideable` ⇒ `Comparable` implication
    /// (Strideable's stdlib definition refines Comparable, so any
    /// Strideable type is by definition Comparable; auto-adding Comparable
    /// lets the macro/plugin emit `checkComparablePropertyLaws` for types
    /// that only spell `: Strideable` in their inheritance clause).
    package static func set(from typeNames: [String]) -> Set<KnownProtocol> {
        var result: Set<KnownProtocol> = []
        var hasEncodable = false
        var hasDecodable = false
        for name in typeNames {
            if let known = from(typeName: name) {
                result.insert(known)
            }
            if name == "Encodable" { hasEncodable = true }
            if name == "Decodable" { hasDecodable = true }
        }
        if hasEncodable && hasDecodable {
            result.insert(.codable)
        }
        if result.contains(.strideable) {
            result.insert(.comparable)
        }
        return result
    }

    /// Protocols whose check functions are *not* emitted by the macro /
    /// plugin from inheritance-clause syntax alone:
    ///
    /// - `IteratorProtocol`'s check is parameterized over a host `Sequence`.
    /// - `Strideable`'s requires a separate `strideGenerator:` over the
    ///   associated `Stride` type.
    /// - `CaseIterable`'s law is static (no per-sample property) and most
    ///   `: CaseIterable` adoptions exist to expose `allCases` for list
    ///   iteration, not to test protocol-level correctness — auto-emitting
    ///   adds noise without meaningful coverage on synthesized
    ///   conformances. Users who do want the law check call
    ///   `checkCaseIterablePropertyLaws` manually.
    ///
    /// All callers filter these out *before* applying `mostSpecific` so that
    /// subsumed peers (notably `Comparable` for Strideable) survive into the
    /// emit set.
    package static let unemittable: Set<KnownProtocol> = [
        .iteratorProtocol,
        .strideable,
        .caseIterable
    ]

    /// Filters `protocols` down to its most-specific members per PRD §4.3
    /// inheritance semantics: when one recognized protocol's check already
    /// runs another's laws via the kit's inheritance chain, the latter is
    /// dropped from the emit set.
    ///
    /// Concretely:
    /// - Hashable subsumes Equatable.
    /// - Comparable subsumes Equatable.
    /// - Strideable subsumes Comparable (and transitively Equatable).
    /// - Collection subsumes Sequence subsumes IteratorProtocol.
    /// - BidirectionalCollection subsumes Collection (transitively).
    /// - RandomAccessCollection subsumes BidirectionalCollection (transitively).
    /// - MutableCollection and RangeReplaceableCollection each subsume
    ///   Collection — they're independent siblings of BidirectionalCollection,
    ///   so a type that's both Bidirectional and RangeReplaceable surfaces both
    ///   checks (one or the other inherits Collection's laws; the other can
    ///   pass `.ownOnly` if the user wants to dedupe further).
    package static func mostSpecific(in protocols: Set<KnownProtocol>) -> Set<KnownProtocol> {
        var result = protocols
        for member in protocols {
            for subsumed in member.subsumedProtocols {
                result.remove(subsumed)
            }
        }
        return result
    }

    private var subsumedProtocols: Set<KnownProtocol> {
        switch self {
        case .hashable, .comparable: return [.equatable]
        case .strideable: return [.comparable]
        case .collection: return [.sequence, .iteratorProtocol]
        case .sequence: return [.iteratorProtocol]
        case .bidirectionalCollection:
            return [.collection, .sequence, .iteratorProtocol]
        case .randomAccessCollection:
            return [.bidirectionalCollection, .collection, .sequence, .iteratorProtocol]
        case .mutableCollection, .rangeReplaceableCollection:
            return [.collection, .sequence, .iteratorProtocol]
        case .numeric: return [.additiveArithmetic]
        case .signedNumeric: return [.numeric, .additiveArithmetic]
        case .binaryInteger: return [.numeric, .additiveArithmetic]
        case .signedInteger:
            return [.binaryInteger, .signedNumeric, .numeric, .additiveArithmetic]
        case .unsignedInteger:
            return [.binaryInteger, .numeric, .additiveArithmetic]
        case .fixedWidthInteger:
            return [.binaryInteger, .numeric, .additiveArithmetic]
        case .floatingPoint:
            // FloatingPoint refines SignedNumeric in stdlib but its
            // `checkFloatingPointPropertyLaws` does NOT auto-run the
            // algebraic chain — IEEE-754 rounding makes exact-equality
            // associativity/distributivity laws fire spurious violations.
            // Subsuming the chain here causes the macro/discovery to drop
            // the inherited checks for `: FloatingPoint` types, which is
            // the desired behavior.
            return [.signedNumeric, .numeric, .additiveArithmetic]
        case .binaryFloatingPoint:
            return [.floatingPoint, .signedNumeric, .numeric, .additiveArithmetic]
        case .stringProtocol:
            // StringProtocol refines BidirectionalCollection in stdlib;
            // its own check auto-runs the BidirectionalCollection chain
            // via .all, so subsume the whole collection-side chain here.
            // Comparable / Hashable / LosslessStringConvertible are
            // siblings (StringProtocol refines them too) but their checks
            // exercise different invariants — keep them un-subsumed so a
            // type spelled `: StringProtocol, Hashable` still emits both.
            return [.bidirectionalCollection, .collection, .sequence, .iteratorProtocol]
        case .monoid:
            // Monoid refines kit-defined Semigroup; checkMonoidPropertyLaws
            // runs Semigroup's combineAssociativity via .all, so a type
            // spelled `: Semigroup, Monoid` emits only the Monoid call.
            return [.semigroup]
        case .commutativeMonoid:
            // CommutativeMonoid refines Monoid; checkCommutativeMonoidPropertyLaws
            // runs Monoid's identity laws and Semigroup's associativity via .all,
            // so a type spelled `: Semigroup, Monoid, CommutativeMonoid` emits
            // only the CommutativeMonoid call.
            return [.monoid, .semigroup]
        case .group:
            // Group refines Monoid (independently of CommutativeMonoid — non-
            // commutative groups are valid); checkGroupPropertyLaws runs
            // Monoid's identity laws and Semigroup's associativity via .all,
            // so a type spelled `: Monoid, Group` emits only the Group call.
            // CommutativeMonoid is NOT subsumed — a type that's both
            // CommutativeMonoid and Group surfaces both checks (incomparable
            // arms in the protocol DAG; see SwiftInferProperties M8 plan
            // open decision #6).
            return [.monoid, .semigroup]
        case .semilattice:
            // Semilattice refines CommutativeMonoid; checkSemilatticePropertyLaws
            // auto-recurses the full chain via .all, so a type spelled
            // `: Semigroup, Monoid, CommutativeMonoid, Semilattice` emits
            // only the Semilattice call.
            return [.commutativeMonoid, .monoid, .semigroup]
        case .ring:
            // Ring is standalone — its two operations (add / multiply) don't
            // share the chain's single `combine`, so it neither subsumes nor
            // is subsumed by the Semigroup→…→Semilattice chain. A type that's
            // both Ring and (via a different op) Monoid surfaces both checks.
            // See Ring.swift and docs/Protocols/v1.10 plan.md "Why standalone".
            return []
        case .equatable, .codable, .iteratorProtocol, .setAlgebra,
             .rawRepresentable, .losslessStringConvertible, .identifiable,
             .caseIterable, .additiveArithmetic, .semigroup: return []
        }
    }

    /// Function-name identifier for the kit's check call, composed as
    /// `check<declarationName>PropertyLaws` — a pure function of
    /// `declarationName`, the single source of truth for each protocol's
    /// spelled name. (Every `check…PropertyLaws` in `PropertyLawKit` follows
    /// this naming convention without exception.)
    package var checkFunctionName: String {
        "check\(declarationName)PropertyLaws"
    }

    /// User-facing protocol name used in diagnostics and inheritance-clause
    /// matching — the spelled form a developer writes after `:` in a Swift
    /// type declaration. The inverse of `KnownProtocol.from(typeName:)`.
    package var declarationName: String {
        switch self {
        case .equatable: return "Equatable"
        case .hashable: return "Hashable"
        case .comparable: return "Comparable"
        case .codable: return "Codable"
        case .iteratorProtocol: return "IteratorProtocol"
        case .sequence: return "Sequence"
        case .collection: return "Collection"
        case .bidirectionalCollection: return "BidirectionalCollection"
        case .randomAccessCollection: return "RandomAccessCollection"
        case .mutableCollection: return "MutableCollection"
        case .rangeReplaceableCollection: return "RangeReplaceableCollection"
        case .setAlgebra: return "SetAlgebra"
        case .strideable: return "Strideable"
        case .rawRepresentable: return "RawRepresentable"
        case .losslessStringConvertible: return "LosslessStringConvertible"
        case .identifiable: return "Identifiable"
        case .caseIterable: return "CaseIterable"
        case .additiveArithmetic: return "AdditiveArithmetic"
        case .numeric: return "Numeric"
        case .signedNumeric: return "SignedNumeric"
        case .binaryInteger: return "BinaryInteger"
        case .signedInteger: return "SignedInteger"
        case .unsignedInteger: return "UnsignedInteger"
        case .fixedWidthInteger: return "FixedWidthInteger"
        case .floatingPoint: return "FloatingPoint"
        case .binaryFloatingPoint: return "BinaryFloatingPoint"
        case .stringProtocol: return "StringProtocol"
        case .semigroup: return "Semigroup"
        case .monoid: return "Monoid"
        case .commutativeMonoid: return "CommutativeMonoid"
        case .group: return "Group"
        case .semilattice: return "Semilattice"
        case .ring: return "Ring"
        }
    }

}

extension KnownProtocol {
    /// `@Test func` name fragment — `<prefix>_<TypeName>` makes generated
    /// tests greppable in test output. It's `declarationName` with a
    /// lower-cased first letter (e.g. `IteratorProtocol` → `iteratorProtocol`),
    /// derived rather than re-listed so the spelled name has one source.
    package var testNameFragment: String {
        let name = declarationName
        return name.prefix(1).lowercased() + name.dropFirst()
    }
}
