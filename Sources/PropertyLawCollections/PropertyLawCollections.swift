// PropertyLawCollections — opt-in law coverage for `apple/swift-collections`.
//
// Phase 1 M0 (collections/async workplan) ships scaffolding plus the
// conformance audit in
// `Tests/PropertyLawCollectionsTests/ConformanceAuditTests.swift`, which pins
// down which stdlib protocols each swift-collections type actually conforms
// to — the matrix that dictates which existing `check…PropertyLaws`
// entrypoints apply when M1 wires generators and law runs per type.
//
// M1+ additions land here: seeded generators for `Deque` / `OrderedSet` /
// `OrderedDictionary` / `Heap` / `BitSet` / `TreeSet` / `TreeDictionary`
// following the `Tests/PropertyLawKitTests/Helpers/Generators.swift`
// conventions, then the new kit-defined law families (OrderPreservationLaws,
// HeapLaws, DequeSymmetryLaws) per the workplan's M3.
