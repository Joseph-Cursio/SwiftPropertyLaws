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
    /// Built from the twelve law enums' `allCases` through the same factories
    /// callers use, so the protocol-name strings are written once and a new
    /// enum case joins the vocabulary without a second edit.
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
    public static let allLawIdentifiers: [LawIdentifier] =
        EquatableLaw.allCases.map(LawIdentifier.equatable)
        + HashableLaw.allCases.map(LawIdentifier.hashable)
        + ComparableLaw.allCases.map(LawIdentifier.comparable)
        + CodableLaw.allCases.map(LawIdentifier.codable)
        + IteratorProtocolLaw.allCases.map(LawIdentifier.iteratorProtocol)
        + SequenceLaw.allCases.map(LawIdentifier.sequence)
        + CollectionLaw.allCases.map(LawIdentifier.collection)
        + BidirectionalCollectionLaw.allCases.map(LawIdentifier.bidirectionalCollection)
        + RandomAccessCollectionLaw.allCases.map(LawIdentifier.randomAccessCollection)
        + MutableCollectionLaw.allCases.map(LawIdentifier.mutableCollection)
        + RangeReplaceableCollectionLaw.allCases.map(LawIdentifier.rangeReplaceableCollection)
        + SetAlgebraLaw.allCases.map(LawIdentifier.setAlgebra)

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
