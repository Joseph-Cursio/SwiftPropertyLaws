import BitCollections
import DequeModule
import HashTreeCollections
import HeapModule
import OrderedCollections
import Testing

// MARK: - Compile-time conformance probes
//
// Each helper compiles only if the conformance holds, so this file *is* the
// conformance matrix for the six swift-collections types the workplan's
// Phase 1 targets. A probe call that stops compiling on a swift-collections
// bump means the matrix changed and the M1 law wiring must be revisited.
// Negative facts (conformances a type deliberately lacks) can't be
// compile-asserted, so they're documented as comments next to each type.

private func probeEquatable<Value: Equatable>(_: Value.Type) {}
private func probeHashable<Value: Hashable>(_: Value.Type) {}
private func probeCodable<Value: Codable>(_: Value.Type) {}
private func probeSequence<Value: Sequence>(_: Value.Type) {}
private func probeCollection<Value: Collection>(_: Value.Type) {}
private func probeBidirectionalCollection<Value: BidirectionalCollection>(_: Value.Type) {}
private func probeRandomAccessCollection<Value: RandomAccessCollection>(_: Value.Type) {}
private func probeMutableCollection<Value: MutableCollection>(_: Value.Type) {}
private func probeRangeReplaceableCollection<Value: RangeReplaceableCollection>(_: Value.Type) {}
private func probeSetAlgebra<Value: SetAlgebra>(_: Value.Type) {}
private func probeSendable<Value: Sendable>(_: Value.Type) {}
private func probeExpressibleByArrayLiteral<Value: ExpressibleByArrayLiteral>(_: Value.Type) {}

@Suite
struct ConformanceAuditTests {

    /// `Deque` is the protocol-richest type: the full Sequence →
    /// RangeReplaceable chain plus MutableCollection, so every existing
    /// collection-family entrypoint applies in M1.
    @Test
    func dequeConformances() {
        probeEquatable(Deque<Int>.self)
        probeHashable(Deque<Int>.self)
        probeCodable(Deque<Int>.self)
        probeSequence(Deque<Int>.self)
        probeCollection(Deque<Int>.self)
        probeBidirectionalCollection(Deque<Int>.self)
        probeRandomAccessCollection(Deque<Int>.self)
        probeMutableCollection(Deque<Int>.self)
        probeRangeReplaceableCollection(Deque<Int>.self)
        probeSendable(Deque<Int>.self)
        probeExpressibleByArrayLiteral(Deque<Int>.self)
        #expect(Deque<Int>().isEmpty)
    }

    /// `OrderedSet` deliberately does NOT conform to `SetAlgebra` — its set
    /// operations are order-asymmetric (`union` keeps left-operand order
    /// first), which breaks SetAlgebra's substitutability expectations.
    /// That asymmetry is the seed of M3's OrderPreservationLaws.
    @Test
    func orderedSetConformances() {
        probeEquatable(OrderedSet<Int>.self)
        probeHashable(OrderedSet<Int>.self)
        probeCodable(OrderedSet<Int>.self)
        probeSequence(OrderedSet<Int>.self)
        probeCollection(OrderedSet<Int>.self)
        probeBidirectionalCollection(OrderedSet<Int>.self)
        probeRandomAccessCollection(OrderedSet<Int>.self)
        probeSendable(OrderedSet<Int>.self)
        probeExpressibleByArrayLiteral(OrderedSet<Int>.self)
        #expect(OrderedSet<Int>().isEmpty)
    }

    /// `OrderedDictionary` is Sequence-only; its random-access surface lives
    /// on the `.elements` / `.values` views, which become the secondary
    /// carriers in M1.
    @Test
    func orderedDictionaryConformances() {
        probeEquatable(OrderedDictionary<Int, Int>.self)
        probeHashable(OrderedDictionary<Int, Int>.self)
        probeCodable(OrderedDictionary<Int, Int>.self)
        probeSequence(OrderedDictionary<Int, Int>.self)
        probeSendable(OrderedDictionary<Int, Int>.self)
        probeRandomAccessCollection(OrderedDictionary<Int, Int>.Elements.self)
        probeRandomAccessCollection(OrderedDictionary<Int, Int>.Values.self)
        probeMutableCollection(OrderedDictionary<Int, Int>.Values.self)
        #expect(OrderedDictionary<Int, Int>().isEmpty)
    }

    /// `Heap` sits almost entirely outside the stdlib protocol lattice —
    /// no Sequence/Collection conformance (iteration order is heap order,
    /// not element order), which is why M3's HeapLaws are model-based
    /// (drain-equals-sorted) rather than protocol-law reuse.
    @Test
    func heapConformances() {
        probeSendable(Heap<Int>.self)
        probeExpressibleByArrayLiteral(Heap<Int>.self)
        var heap = Heap<Int>()
        heap.insert(3)
        #expect(heap.min == 3)
    }

    /// `BitSet` is the full-SetAlgebra carrier that motivates M2's family
    /// completion (distributivity / absorption / relative De Morgan).
    @Test
    func bitSetConformances() {
        probeEquatable(BitSet.self)
        probeHashable(BitSet.self)
        probeCodable(BitSet.self)
        probeSequence(BitSet.self)
        probeCollection(BitSet.self)
        probeBidirectionalCollection(BitSet.self)
        probeSetAlgebra(BitSet.self)
        probeSendable(BitSet.self)
        probeExpressibleByArrayLiteral(BitSet.self)
        #expect(BitSet().isEmpty)
    }

    /// `TreeSet` (CHAMP): SetAlgebra + Collection; persistence semantics are
    /// exercised by the existing ValueSemantic/DefensiveCopy families in M1.
    @Test
    func treeSetConformances() {
        probeEquatable(TreeSet<Int>.self)
        probeHashable(TreeSet<Int>.self)
        probeCodable(TreeSet<Int>.self)
        probeSequence(TreeSet<Int>.self)
        probeCollection(TreeSet<Int>.self)
        probeSetAlgebra(TreeSet<Int>.self)
        probeSendable(TreeSet<Int>.self)
        probeExpressibleByArrayLiteral(TreeSet<Int>.self)
        #expect(TreeSet<Int>().isEmpty)
    }

    /// `TreeDictionary` (CHAMP): like `OrderedDictionary`, the dictionary
    /// itself is the Equatable/Hashable/Codable carrier while collection
    /// laws run against its views.
    @Test
    func treeDictionaryConformances() {
        probeEquatable(TreeDictionary<Int, Int>.self)
        probeHashable(TreeDictionary<Int, Int>.self)
        probeCodable(TreeDictionary<Int, Int>.self)
        probeSequence(TreeDictionary<Int, Int>.self)
        probeSendable(TreeDictionary<Int, Int>.self)
        #expect(TreeDictionary<Int, Int>().isEmpty)
    }
}
