// The law enums and `LawIdentifier` factories for the suites added after the
// first twelve. `LawIdentifier.allLawIdentifiers`, in `LawIdentifier.swift`,
// reads every one of them. They are in their own file only to keep that one
// within the file-length limit.

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

public enum StrictWeakOrderingLaw: String, Sendable, Hashable, CaseIterable {
    case irreflexivity, asymmetry, transitivity, incomparabilityTransitivity
    case discrimination, congruence
}

public enum BinaryIntegerLaw: String, Sendable, Hashable, CaseIterable {
    case bitwiseAndCommutativity, bitwiseAndDistributesOverOr, bitwiseAndIdempotence
    case bitwiseDeMorgan, bitwiseDoubleNegation, bitwiseOrCommutativity
    case bitwiseOrIdempotence, bitwiseXorSelfIsZero, bitwiseXorZeroIdentity
    case divisionByOneIdentity, divisionMultiplicationRoundTrip
    case quotientAndRemainderConsistency, remainderMagnitudeBound, selfDivisionIsOne
    case shiftByZeroIdentity, trailingZeroBitCountRange
}

public extension LawIdentifier {
    /// Names one of the `ActionIdempotenceInvariant` laws, for a `LawSuppression`.
    static func actionIdempotenceInvariant(_ law: ActionIdempotenceInvariantLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "ActionIdempotenceInvariant", lawName: law.rawValue)
    }

    /// Names one of the `AdditiveArithmetic` laws, for a `LawSuppression`.
    static func additiveArithmetic(_ law: AdditiveArithmeticLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "AdditiveArithmetic", lawName: law.rawValue)
    }

    /// Names one of the `BinaryFloatingPoint` laws, for a `LawSuppression`.
    static func binaryFloatingPoint(_ law: BinaryFloatingPointLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "BinaryFloatingPoint", lawName: law.rawValue)
    }

    /// Names one of the `BinaryInteger` laws, for a `LawSuppression`.
    static func binaryInteger(_ law: BinaryIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "BinaryInteger", lawName: law.rawValue)
    }

    /// Names one of the `CaseIterable` laws, for a `LawSuppression`.
    static func caseIterable(_ law: CaseIterableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "CaseIterable", lawName: law.rawValue)
    }

    /// Names one of the `CommutativeMonoid` laws, for a `LawSuppression`.
    static func commutativeMonoid(_ law: CommutativeMonoidLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "CommutativeMonoid", lawName: law.rawValue)
    }

    /// Names one of the `DefensiveCopy` laws, for a `LawSuppression`.
    static func defensiveCopy(_ law: DefensiveCopyLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "DefensiveCopy", lawName: law.rawValue)
    }

    /// Names one of the `FixedWidthInteger` laws, for a `LawSuppression`.
    static func fixedWidthInteger(_ law: FixedWidthIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "FixedWidthInteger", lawName: law.rawValue)
    }

    /// Names one of the `FloatingPoint` laws, for a `LawSuppression`.
    static func floatingPoint(_ law: FloatingPointLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "FloatingPoint", lawName: law.rawValue)
    }

    /// Names one of the `Group` laws, for a `LawSuppression`.
    static func group(_ law: GroupLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Group", lawName: law.rawValue)
    }

    /// Names one of the `Identifiable` laws, for a `LawSuppression`.
    static func identifiable(_ law: IdentifiableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Identifiable", lawName: law.rawValue)
    }

    /// Names one of the `InteractionInvariant` laws, for a `LawSuppression`.
    static func interactionInvariant(_ law: InteractionInvariantLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "InteractionInvariant", lawName: law.rawValue)
    }

    /// Names one of the `LosslessStringConvertible` laws, for a `LawSuppression`.
    static func losslessStringConvertible(_ law: LosslessStringConvertibleLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "LosslessStringConvertible", lawName: law.rawValue)
    }

    /// Names one of the `Monoid` laws, for a `LawSuppression`.
    static func monoid(_ law: MonoidLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Monoid", lawName: law.rawValue)
    }

    /// Names one of the `Numeric` laws, for a `LawSuppression`.
    static func numeric(_ law: NumericLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Numeric", lawName: law.rawValue)
    }

    /// Names one of the `RawRepresentable` laws, for a `LawSuppression`.
    static func rawRepresentable(_ law: RawRepresentableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "RawRepresentable", lawName: law.rawValue)
    }

    /// Names one of the `Ring` laws, for a `LawSuppression`.
    static func ring(_ law: RingLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Ring", lawName: law.rawValue)
    }

    /// Names one of the `Semigroup` laws, for a `LawSuppression`.
    static func semigroup(_ law: SemigroupLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Semigroup", lawName: law.rawValue)
    }

    /// Names one of the `Semilattice` laws, for a `LawSuppression`.
    static func semilattice(_ law: SemilatticeLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Semilattice", lawName: law.rawValue)
    }

    /// Names one of the `SignedInteger` laws, for a `LawSuppression`.
    static func signedInteger(_ law: SignedIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "SignedInteger", lawName: law.rawValue)
    }

    /// Names one of the `SignedNumeric` laws, for a `LawSuppression`.
    static func signedNumeric(_ law: SignedNumericLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "SignedNumeric", lawName: law.rawValue)
    }

    /// Names one of the `StableIdentity` laws, for a `LawSuppression`.
    static func stableIdentity(_ law: StableIdentityLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "StableIdentity", lawName: law.rawValue)
    }

    /// Names one of the `Strideable` laws, for a `LawSuppression`.
    static func strideable(_ law: StrideableLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "Strideable", lawName: law.rawValue)
    }

    /// Names one of the `StringProtocol` laws, for a `LawSuppression`.
    static func stringProtocol(_ law: StringProtocolLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "StringProtocol", lawName: law.rawValue)
    }

    /// Names one of the `UnsignedInteger` laws, for a `LawSuppression`.
    static func unsignedInteger(_ law: UnsignedIntegerLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "UnsignedInteger", lawName: law.rawValue)
    }

    /// Names one of the `ValueSemantic` laws, for a `LawSuppression`.
    static func valueSemantic(_ law: ValueSemanticLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "ValueSemantic", lawName: law.rawValue)
    }
}

public extension LawIdentifier {
    /// Names one of the `StrictWeakOrdering` laws, for a `LawSuppression`.
    static func strictWeakOrdering(_ law: StrictWeakOrderingLaw) -> LawIdentifier {
        LawIdentifier(protocolName: "StrictWeakOrdering", lawName: law.rawValue)
    }
}
