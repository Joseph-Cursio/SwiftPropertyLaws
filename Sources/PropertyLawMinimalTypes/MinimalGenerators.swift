import PropertyBased

/// Seeded generators for the minimal conformances, matching the element range and length
/// conventions the other collection generators use.
public extension Gen where Value == MinimalCollection<Int> {

    static func smallIntMinimalCollection(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<MinimalCollection<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { MinimalCollection($0) }
    }
}

public extension Gen where Value == MinimalBidirectionalCollection<Int> {

    static func smallIntMinimalBidirectionalCollection(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<MinimalBidirectionalCollection<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { MinimalBidirectionalCollection($0) }
    }
}

public extension Gen where Value == MinimalSequence<Int> {

    static func smallIntMinimalSequence(
        count: ClosedRange<Int> = 0 ... 8
    ) -> Generator<MinimalSequence<Int>, some SendableSequenceType> {
        Gen<Int>.int(in: -100 ... 100).array(of: count).map { MinimalSequence($0) }
    }
}
