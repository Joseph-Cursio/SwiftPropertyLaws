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
        let head = checkResultLaw.split(separator: "[", maxSplits: 1).first.map(String.init)
            ?? checkResultLaw
        return head == qualifiedName
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
}
