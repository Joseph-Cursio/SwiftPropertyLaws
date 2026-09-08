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
}

extension LawIdentifier {
    public static func equatable(_ law: EquatableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Equatable", lawName: law.rawValue)
    }
    public static func hashable(_ law: HashableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Hashable", lawName: law.rawValue)
    }
    public static func comparable(_ law: ComparableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Comparable", lawName: law.rawValue)
    }
    public static func codable(_ law: CodableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Codable", lawName: law.rawValue)
    }
    public static func iteratorProtocol(_ law: IteratorProtocolLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "IteratorProtocol", lawName: law.rawValue)
    }
    public static func sequence(_ law: SequenceLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Sequence", lawName: law.rawValue)
    }
    public static func collection(_ law: CollectionLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Collection", lawName: law.rawValue)
    }
    public static func bidirectionalCollection(
        _ law: BidirectionalCollectionLaw
    ) -> LawIdentifier {
        LawIdentifier(protocolName: "BidirectionalCollection", lawName: law.rawValue)
    }
    public static func randomAccessCollection(
        _ law: RandomAccessCollectionLaw
    ) -> LawIdentifier {
        LawIdentifier(protocolName: "RandomAccessCollection", lawName: law.rawValue)
    }
    public static func mutableCollection(_ law: MutableCollectionLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "MutableCollection", lawName: law.rawValue)
    }
    public static func rangeReplaceableCollection(
        _ law: RangeReplaceableCollectionLaw
    ) -> LawIdentifier {
        LawIdentifier(protocolName: "RangeReplaceableCollection", lawName: law.rawValue)
    }
    public static func setAlgebra(_ law: SetAlgebraLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "SetAlgebra", lawName: law.rawValue)
    }
}

public enum EquatableLaw: String, Sendable, Hashable, CaseIterable {
    case reflexivity, symmetry, transitivity, negationConsistency
}

public enum HashableLaw: String, Sendable, Hashable, CaseIterable {
    case equalityConsistency, stabilityWithinProcess, distribution
}

public enum ComparableLaw: String, Sendable, Hashable, CaseIterable {
    case antisymmetry, transitivity, totality, operatorConsistency
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

// MARK: - The vocabulary

extension LawIdentifier {

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
    public static let allLawIdentifiers: [LawIdentifier] = {
        // Statements rather than one `+` chain: a 39-term chain exceeds the
        // type checker's budget outright, and a shorter one has tripped CI
        // timeouts in this codebase's history while compiling locally.
        var result: [LawIdentifier] = []
        result += ActionIdempotenceInvariantLaw.allCases.map(LawIdentifier.actionIdempotenceInvariant)
        result += AdditiveArithmeticLaw.allCases.map(LawIdentifier.additiveArithmetic)
        result += BidirectionalCollectionLaw.allCases.map(LawIdentifier.bidirectionalCollection)
        result += BinaryFloatingPointLaw.allCases.map(LawIdentifier.binaryFloatingPoint)
        result += BinaryIntegerLaw.allCases.map(LawIdentifier.binaryInteger)
        result += CaseIterableLaw.allCases.map(LawIdentifier.caseIterable)
        result += CodableLaw.allCases.map(LawIdentifier.codable)
        result += CollectionLaw.allCases.map(LawIdentifier.collection)
        result += CommutativeMonoidLaw.allCases.map(LawIdentifier.commutativeMonoid)
        result += ComparableLaw.allCases.map(LawIdentifier.comparable)
        result += DefensiveCopyLaw.allCases.map(LawIdentifier.defensiveCopy)
        result += EquatableLaw.allCases.map(LawIdentifier.equatable)
        result += FixedWidthIntegerLaw.allCases.map(LawIdentifier.fixedWidthInteger)
        result += FloatingPointLaw.allCases.map(LawIdentifier.floatingPoint)
        result += GroupLaw.allCases.map(LawIdentifier.group)
        result += HashableLaw.allCases.map(LawIdentifier.hashable)
        result += IdentifiableLaw.allCases.map(LawIdentifier.identifiable)
        result += InteractionInvariantLaw.allCases.map(LawIdentifier.interactionInvariant)
        result += IteratorProtocolLaw.allCases.map(LawIdentifier.iteratorProtocol)
        result += LosslessStringConvertibleLaw.allCases.map(LawIdentifier.losslessStringConvertible)
        result += MonoidLaw.allCases.map(LawIdentifier.monoid)
        result += MutableCollectionLaw.allCases.map(LawIdentifier.mutableCollection)
        result += NumericLaw.allCases.map(LawIdentifier.numeric)
        result += RandomAccessCollectionLaw.allCases.map(LawIdentifier.randomAccessCollection)
        result += RangeReplaceableCollectionLaw.allCases.map(LawIdentifier.rangeReplaceableCollection)
        result += RawRepresentableLaw.allCases.map(LawIdentifier.rawRepresentable)
        result += RingLaw.allCases.map(LawIdentifier.ring)
        result += SemigroupLaw.allCases.map(LawIdentifier.semigroup)
        result += SemilatticeLaw.allCases.map(LawIdentifier.semilattice)
        result += SequenceLaw.allCases.map(LawIdentifier.sequence)
        result += SetAlgebraLaw.allCases.map(LawIdentifier.setAlgebra)
        result += StrictWeakOrderingLaw.allCases.map(LawIdentifier.strictWeakOrdering)
        result += SignedIntegerLaw.allCases.map(LawIdentifier.signedInteger)
        result += SignedNumericLaw.allCases.map(LawIdentifier.signedNumeric)
        result += StableIdentityLaw.allCases.map(LawIdentifier.stableIdentity)
        result += StrideableLaw.allCases.map(LawIdentifier.strideable)
        result += StringProtocolLaw.allCases.map(LawIdentifier.stringProtocol)
        result += TransformationLaw.allCases.map(LawIdentifier.transformation)
        result += UnsignedIntegerLaw.allCases.map(LawIdentifier.unsignedInteger)
        result += ValueSemanticLaw.allCases.map(LawIdentifier.valueSemantic)
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

// MARK: - Law enums for the suites the first twelve missed

public enum ActionIdempotenceInvariantLaw: String, Sendable, Hashable, CaseIterable {
    case doubleApplicationEqualsSingle
}

public enum AdditiveArithmeticLaw: String, Sendable, Hashable, CaseIterable {
    case additionAssociativity, additionCommutativity, selfSubtractionIsZero
    case subtractionInverse, zeroAdditiveIdentity
}

public enum BinaryFloatingPointLaw: String, Sendable, Hashable, CaseIterable {
    case binadeMembership, convertingFromIntegerExactness, radix
    case significandExponentReconstruction
}

public enum BinaryIntegerLaw: String, Sendable, Hashable, CaseIterable {
    case bitwiseAndCommutativity, bitwiseAndDistributesOverOr, bitwiseAndIdempotence
    case bitwiseDeMorgan, bitwiseDoubleNegation, bitwiseOrCommutativity
    case bitwiseOrIdempotence, bitwiseXorSelfIsZero, bitwiseXorZeroIdentity
    case divisionByOneIdentity, divisionMultiplicationRoundTrip
    case quotientAndRemainderConsistency, remainderMagnitudeBound, selfDivisionIsOne
    case shiftByZeroIdentity, trailingZeroBitCountRange
}

public enum CaseIterableLaw: String, Sendable, Hashable, CaseIterable {
    case exactlyOnce
}

public enum CommutativeMonoidLaw: String, Sendable, Hashable, CaseIterable {
    case combineCommutativity
}

public enum DefensiveCopyLaw: String, Sendable, Hashable, CaseIterable {
    case copyIsDistinctInstance, copyIsIndependent
}

public enum FixedWidthIntegerLaw: String, Sendable, Hashable, CaseIterable {
    case addingReportingOverflowConsistency, bitWidthMatchesType, byteSwappedInvolution
    case dividedReportingOverflowOnDivByZero, minMaxBoundsAreReachable
    case multipliedReportingOverflowConsistency, nonzeroBitCountRange
    case subtractingReportingOverflowConsistency, wrappingArithmeticDoesNotTrap
}

public enum FloatingPointLaw: String, Sendable, Hashable, CaseIterable {
    case absoluteValueNonNegative, additionCommutativity, additiveInverseFinite
    case infinityIsInfinite, multiplicationCommutativity, nanComparisonIsUnordered
    case nanInequality, nanIsNaN, nanPropagatesAddition, nanPropagatesMultiplication
    case negativeInfinityComparison, nextUpDownRoundTrip, roundedZeroIdentity
    case signMatchesIsLessThanZero, signedZeroEquality, zeroIsZero
}

public enum GroupLaw: String, Sendable, Hashable, CaseIterable {
    case combineLeftInverse, combineRightInverse
}

public enum IdentifiableLaw: String, Sendable, Hashable, CaseIterable {
    case idStability
}

public enum InteractionInvariantLaw: String, Sendable, Hashable, CaseIterable {
    case invariantHoldsAfterEachStep, isFalsifiable
}

public enum LosslessStringConvertibleLaw: String, Sendable, Hashable, CaseIterable {
    case roundTrip
}

public enum MonoidLaw: String, Sendable, Hashable, CaseIterable {
    case combineLeftIdentity, combineRightIdentity
}

public enum NumericLaw: String, Sendable, Hashable, CaseIterable {
    case leftDistributivity, multiplicationAssociativity, multiplicationCommutativity
    case oneMultiplicativeIdentity, rightDistributivity, zeroAnnihilation
}

public enum RawRepresentableLaw: String, Sendable, Hashable, CaseIterable {
    case roundTrip
}

public enum RingLaw: String, Sendable, Hashable, CaseIterable {
    case addAssociativity, addCommutativity, addLeftIdentity, addLeftInverse
    case addRightIdentity, addRightInverse, leftDistributivity, multiplyAssociativity
    case multiplyLeftIdentity, multiplyRightIdentity, rightDistributivity
}

public enum SemigroupLaw: String, Sendable, Hashable, CaseIterable {
    case combineAssociativity
}

public enum SemilatticeLaw: String, Sendable, Hashable, CaseIterable {
    case combineIdempotence
}

public enum SignedIntegerLaw: String, Sendable, Hashable, CaseIterable {
    case signednessConsistency
}

public enum SignedNumericLaw: String, Sendable, Hashable, CaseIterable {
    case additiveInverse, negateMutationConsistency, negationDistributesOverAddition
    case negationInvolution
}

public enum StableIdentityLaw: String, Sendable, Hashable, CaseIterable {
    case equalityStableUnderMutation, hashStableUnderMutation
}

public enum StrideableLaw: String, Sendable, Hashable, CaseIterable {
    case advanceRoundTrip, distanceRoundTrip, selfDistanceIsZero, zeroAdvanceIdentity
}

public enum StringProtocolLaw: String, Sendable, Hashable, CaseIterable {
    case countMatchesStringInit, hasPrefixEmpty, hasSuffixEmpty, isEmptyMatchesCountZero
    case lowercasedIdempotent, stringInitRoundTrip, uppercasedIdempotent, utf
}

public enum UnsignedIntegerLaw: String, Sendable, Hashable, CaseIterable {
    case magnitudeIsSelf, nonNegative
}

public enum ValueSemanticLaw: String, Sendable, Hashable, CaseIterable {
    case copyMutationDoesNotLeak, copyMutationDoesNotLeakUnderInterleaving
}

extension LawIdentifier {
    public static func actionIdempotenceInvariant(_ law: ActionIdempotenceInvariantLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "ActionIdempotenceInvariant", lawName: law.rawValue)
    }

    public static func additiveArithmetic(_ law: AdditiveArithmeticLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "AdditiveArithmetic", lawName: law.rawValue)
    }

    public static func binaryFloatingPoint(_ law: BinaryFloatingPointLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "BinaryFloatingPoint", lawName: law.rawValue)
    }

    public static func binaryInteger(_ law: BinaryIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "BinaryInteger", lawName: law.rawValue)
    }

    public static func caseIterable(_ law: CaseIterableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "CaseIterable", lawName: law.rawValue)
    }

    public static func commutativeMonoid(_ law: CommutativeMonoidLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "CommutativeMonoid", lawName: law.rawValue)
    }

    public static func defensiveCopy(_ law: DefensiveCopyLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "DefensiveCopy", lawName: law.rawValue)
    }

    public static func fixedWidthInteger(_ law: FixedWidthIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "FixedWidthInteger", lawName: law.rawValue)
    }

    public static func floatingPoint(_ law: FloatingPointLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "FloatingPoint", lawName: law.rawValue)
    }

    public static func group(_ law: GroupLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Group", lawName: law.rawValue)
    }

    public static func identifiable(_ law: IdentifiableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Identifiable", lawName: law.rawValue)
    }

    public static func interactionInvariant(_ law: InteractionInvariantLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "InteractionInvariant", lawName: law.rawValue)
    }

    public static func losslessStringConvertible(_ law: LosslessStringConvertibleLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "LosslessStringConvertible", lawName: law.rawValue)
    }

    public static func monoid(_ law: MonoidLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Monoid", lawName: law.rawValue)
    }

    public static func numeric(_ law: NumericLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Numeric", lawName: law.rawValue)
    }

    public static func rawRepresentable(_ law: RawRepresentableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "RawRepresentable", lawName: law.rawValue)
    }

    public static func ring(_ law: RingLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Ring", lawName: law.rawValue)
    }

    public static func semigroup(_ law: SemigroupLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Semigroup", lawName: law.rawValue)
    }

    public static func semilattice(_ law: SemilatticeLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Semilattice", lawName: law.rawValue)
    }

    public static func signedInteger(_ law: SignedIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "SignedInteger", lawName: law.rawValue)
    }

    public static func signedNumeric(_ law: SignedNumericLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "SignedNumeric", lawName: law.rawValue)
    }

    public static func stableIdentity(_ law: StableIdentityLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "StableIdentity", lawName: law.rawValue)
    }

    public static func strideable(_ law: StrideableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Strideable", lawName: law.rawValue)
    }

    public static func stringProtocol(_ law: StringProtocolLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "StringProtocol", lawName: law.rawValue)
    }

    public static func unsignedInteger(_ law: UnsignedIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "UnsignedInteger", lawName: law.rawValue)
    }

    public static func valueSemantic(_ law: ValueSemanticLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "ValueSemantic", lawName: law.rawValue)
    }

}

public enum StrictWeakOrderingLaw: String, Sendable, Hashable, CaseIterable {
    case irreflexivity, asymmetry, transitivity, incomparabilityTransitivity
    case discrimination, congruence
}

extension LawIdentifier {
    public static func strictWeakOrdering(_ law: StrictWeakOrderingLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "StrictWeakOrdering", lawName: law.rawValue)
    }
}
