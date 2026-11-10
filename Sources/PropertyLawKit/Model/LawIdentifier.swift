public enum EquatableLaw: String, Sendable, Hashable, CaseIterable {
    case reflexivity, symmetry, transitivity, negationConsistency
}

public enum HashableLaw: String, Sendable, Hashable, CaseIterable {
    case equalityConsistency, stabilityWithinProcess, distribution
}

public enum ComparableLaw: String, Sendable, Hashable, CaseIterable {
    case irreflexivity, antisymmetry, transitivity, totality, operatorConsistency
}

public enum CodableLaw: String, Sendable, Hashable, CaseIterable {
    case roundTripFidelity
}

public enum IteratorProtocolLaw: String, Sendable, Hashable, CaseIterable {
    case terminationStability, singlePassYield
}

public enum SequenceLaw: String, Sendable, Hashable, CaseIterable {
    case underestimatedCountLowerBound, multiPassConsistency, makeIteratorIndependence
}

public enum CollectionLaw: String, Sendable, Hashable, CaseIterable {
    case countConsistency, indexValidity, nonMutation
}

public enum BidirectionalCollectionLaw: String, Sendable, Hashable, CaseIterable {
    case indexBeforeAfterRoundTrip, indexAfterBeforeRoundTrip, reverseTraversalConsistency
}

public enum RandomAccessCollectionLaw: String, Sendable, Hashable, CaseIterable {
    case distanceConsistency, offsetConsistency, negativeOffsetInversion
}

public enum MutableCollectionLaw: String, Sendable, Hashable, CaseIterable {
    case swapAtInvolution, swapAtSwapsValues
}

public enum RangeReplaceableCollectionLaw: String, Sendable, Hashable, CaseIterable {
    case emptyInitIsEmpty, removeAtInsertRoundTrip, removeAllMakesEmpty, replaceSubrangeAppliesEdit
}

public enum SetAlgebraLaw: String, Sendable, Hashable, CaseIterable {
    case unionIdempotence, intersectionIdempotence
    case unionCommutativity, intersectionCommutativity
    case emptyIdentity
    case symmetricDifferenceSelfIsEmpty
    case symmetricDifferenceEmptyIdentity
    case symmetricDifferenceCommutativity
    case symmetricDifferenceDefinition
    case unionDistributivity, intersectionDistributivity
    case unionAbsorption, intersectionAbsorption
    case deMorganForUnion, deMorganForIntersection
    case formUnionMatchesUnion, formIntersectionMatchesIntersection
    case subtractMatchesSubtracting
    case formSymmetricDifferenceMatchesSymmetricDifference
}

/// Names a single protocol law for suppression matching (PRD §4.7).
///
/// `protocolName` is the bare protocol name (`"Equatable"`, `"Hashable"`).
/// `lawName` is the trailing identifier of the law as it appears in
/// `CheckResult.protocolLaw` (`"reflexivity"`, `"equalityConsistency"`).
///
/// Matching against a `CheckResult` is by exact equality on the
/// `"<protocol>.<law>"` string, ignoring any backend-specific suffix the
/// runner appends in brackets (e.g. `Codable.roundTripFidelity[JSON]` is
/// matched by `LawIdentifier(protocolName: "Codable", lawName: "roundTripFidelity")`).
public struct LawIdentifier: Sendable, Hashable {
    public let protocolName: String
    public let lawName: String

    public init(protocolName: String, lawName: String) {
        self.protocolName = protocolName
        self.lawName = lawName
    }

    public var qualifiedName: String { "\(protocolName).\(lawName)" }

    func matches(_ checkResultLaw: String) -> Bool {
        Self.baseName(of: checkResultLaw) == qualifiedName
    }

    /// A `CheckResult.protocolLaw` with any backend-specific suffix removed.
    ///
    /// The runner appends a bracketed discriminator to laws that run once per
    /// backend — `Codable.roundTripFidelity[JSON]`. `CodableLaw` has one case,
    /// `roundTripFidelity`, so the emitted name is not an enum case and never
    /// will be. Everything comparing an emitted law to this module's vocabulary
    /// has to strip the suffix first, which is why this is public rather than
    /// left inline in `matches`.
    public static func baseName(of checkResultLaw: String) -> String {
        checkResultLaw.split(separator: "[", maxSplits: 1).first.map(String.init)
            ?? checkResultLaw
    }

    /// Names one of the `Equatable` laws, for a `LawSuppression`.
    public static func equatable(_ law: EquatableLaw) -> Self {
        Self(protocolName: "Equatable", lawName: law.rawValue)
    }
    /// Names one of the `Hashable` laws, for a `LawSuppression`.
    public static func hashable(_ law: HashableLaw) -> Self {
        Self(protocolName: "Hashable", lawName: law.rawValue)
    }
    /// Names one of the `Comparable` laws, for a `LawSuppression`.
    public static func comparable(_ law: ComparableLaw) -> Self {
        Self(protocolName: "Comparable", lawName: law.rawValue)
    }
    /// Names one of the `Codable` laws, for a `LawSuppression`.
    public static func codable(_ law: CodableLaw) -> Self {
        Self(protocolName: "Codable", lawName: law.rawValue)
    }
    /// Names one of the `IteratorProtocol` laws, for a `LawSuppression`.
    public static func iteratorProtocol(_ law: IteratorProtocolLaw) -> Self {
        Self(protocolName: "IteratorProtocol", lawName: law.rawValue)
    }
    /// Names one of the `Sequence` laws, for a `LawSuppression`.
    public static func sequence(_ law: SequenceLaw) -> Self {
        Self(protocolName: "Sequence", lawName: law.rawValue)
    }
    /// Names one of the `Collection` laws, for a `LawSuppression`.
    public static func collection(_ law: CollectionLaw) -> Self {
        Self(protocolName: "Collection", lawName: law.rawValue)
    }
    /// Names one of the `BidirectionalCollection` laws, for a `LawSuppression`.
    public static func bidirectionalCollection(
        _ law: BidirectionalCollectionLaw
    ) -> Self {
        Self(protocolName: "BidirectionalCollection", lawName: law.rawValue)
    }
    /// Names one of the `RandomAccessCollection` laws, for a `LawSuppression`.
    public static func randomAccessCollection(
        _ law: RandomAccessCollectionLaw
    ) -> Self {
        Self(protocolName: "RandomAccessCollection", lawName: law.rawValue)
    }
    /// Names one of the `MutableCollection` laws, for a `LawSuppression`.
    public static func mutableCollection(_ law: MutableCollectionLaw) -> Self {
        Self(protocolName: "MutableCollection", lawName: law.rawValue)
    }
    /// Names one of the `RangeReplaceableCollection` laws, for a `LawSuppression`.
    public static func rangeReplaceableCollection(
        _ law: RangeReplaceableCollectionLaw
    ) -> Self {
        Self(protocolName: "RangeReplaceableCollection", lawName: law.rawValue)
    }
    /// Names one of the `SetAlgebra` laws, for a `LawSuppression`.
    public static func setAlgebra(_ law: SetAlgebraLaw) -> Self {
        Self(protocolName: "SetAlgebra", lawName: law.rawValue)
    }

    /// Every law this module can emit.
    ///
    /// Built from every law enum's `allCases` through the same factories callers
    /// use, so the protocol-name strings are written once and a new enum case
    /// joins the vocabulary without a second edit.
    ///
    /// **This was wrong when introduced.** It covered twelve enums while the
    /// module emits laws for 39 protocols, and claimed to be every law the
    /// module can emit. `isKnownLawName` therefore returned `false` for laws the
    /// kit genuinely runs — `Semilattice.combineIdempotence` among them. The
    /// test meant to catch that ran four suites, all of them twelve-enum ones,
    /// so it confirmed the vocabulary against the part of the kit it was built
    /// from.
    ///
    /// **Why this is public.** A consumer that wants to know whether a law name
    /// is real has otherwise to scan this package's *sources* — which means
    /// reading whatever happens to be in `.build/checkouts` rather than the
    /// version actually linked, failing outright against a binary dependency,
    /// and matching string literals wherever they appear, including in doc
    /// comments. `SwiftInferProperties` does exactly that today, in two
    /// hand-copied places, to validate a table asserting which laws this kit
    /// runs. That table is a claim about this module, and this module is where
    /// the answer should come from.
    ///
    /// Deliberately not an exhaustive `switch` anywhere: adding a law must stay
    /// source-compatible for downstream packages.
    public static let allLawIdentifiers: [Self] = { // swiftlint:disable:this closure_body_length
        // Statements rather than one `+` chain: a 39-term chain exceeds the
        // type checker's budget outright, and a shorter one has tripped CI
        // timeouts in this codebase's history while compiling locally.
        var result: [Self] = []
        result += ActionIdempotenceInvariantLaw.allCases.map(Self.actionIdempotenceInvariant)
        result += AdditiveArithmeticLaw.allCases.map(Self.additiveArithmetic)
        result += BidirectionalCollectionLaw.allCases.map(Self.bidirectionalCollection)
        result += BinaryFloatingPointLaw.allCases.map(Self.binaryFloatingPoint)
        result += BinaryIntegerLaw.allCases.map(Self.binaryInteger)
        result += CaseIterableLaw.allCases.map(Self.caseIterable)
        result += CodableLaw.allCases.map(Self.codable)
        result += CollectionLaw.allCases.map(Self.collection)
        result += CommutativeMonoidLaw.allCases.map(Self.commutativeMonoid)
        result += ComparableLaw.allCases.map(Self.comparable)
        result += DefensiveCopyLaw.allCases.map(Self.defensiveCopy)
        result += EquatableLaw.allCases.map(Self.equatable)
        result += FixedWidthIntegerLaw.allCases.map(Self.fixedWidthInteger)
        result += FloatingPointLaw.allCases.map(Self.floatingPoint)
        result += GroupLaw.allCases.map(Self.group)
        result += HashableLaw.allCases.map(Self.hashable)
        result += IdentifiableLaw.allCases.map(Self.identifiable)
        result += InteractionInvariantLaw.allCases.map(Self.interactionInvariant)
        result += IteratorProtocolLaw.allCases.map(Self.iteratorProtocol)
        result += LosslessStringConvertibleLaw.allCases.map(Self.losslessStringConvertible)
        result += MonoidLaw.allCases.map(Self.monoid)
        result += MutableCollectionLaw.allCases.map(Self.mutableCollection)
        result += NumericLaw.allCases.map(Self.numeric)
        result += RandomAccessCollectionLaw.allCases.map(Self.randomAccessCollection)
        result += RangeReplaceableCollectionLaw.allCases.map(Self.rangeReplaceableCollection)
        result += RawRepresentableLaw.allCases.map(Self.rawRepresentable)
        result += RingLaw.allCases.map(Self.ring)
        result += SemigroupLaw.allCases.map(Self.semigroup)
        result += SemilatticeLaw.allCases.map(Self.semilattice)
        result += SequenceLaw.allCases.map(Self.sequence)
        result += SetAlgebraLaw.allCases.map(Self.setAlgebra)
        result += StrictWeakOrderingLaw.allCases.map(Self.strictWeakOrdering)
        result += SignedIntegerLaw.allCases.map(Self.signedInteger)
        result += SignedNumericLaw.allCases.map(Self.signedNumeric)
        result += StableIdentityLaw.allCases.map(Self.stableIdentity)
        result += StrideableLaw.allCases.map(Self.strideable)
        result += StringProtocolLaw.allCases.map(Self.stringProtocol)
        result += TransformationLaw.allCases.map(Self.transformation)
        result += UnsignedIntegerLaw.allCases.map(Self.unsignedInteger)
        result += ValueSemanticLaw.allCases.map(Self.valueSemantic)
        return result
    }()

    /// Every law name this module can emit, as `"<Protocol>.<law>"`.
    ///
    /// **Base names.** A law that runs once per backend is emitted with a
    /// bracketed suffix that is not in this set; normalise with
    /// `baseName(of:)`, or use `isKnownLawName(_:)` which does it for you.
    public static let allLawNames: Set<String> =
        Set(allLawIdentifiers.map(\.qualifiedName))

    /// Whether `checkResultLaw` names a law this module can emit, ignoring any
    /// backend-specific suffix.
    public static func isKnownLawName(_ checkResultLaw: String) -> Bool {
        allLawNames.contains(baseName(of: checkResultLaw))
    }
}

// MARK: - The vocabulary
