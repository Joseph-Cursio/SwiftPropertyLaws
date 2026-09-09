import DequeModule
import PropertyLawKit

/// Every internal ring-buffer arrangement a `Deque` can be in, as a bounded
/// space.
///
/// **This exists because of a measured gap.** `Gen.smallIntDeque` builds every
/// deque the kit tests as `Deque(array)`, and an array-built deque always lays
/// its buffer out from slot 0. Over 1 000 draws that path produced 1 000
/// contiguous deques and **zero wrapped ones** — not rarely, never. So every
/// `Deque` law the kit ships has only ever run against one layout, and no trial
/// budget fixes it: `.exhaustive(10_000)` draws ten thousand contiguous deques.
///
/// A layout cannot be *drawn*, it has to be *built*: the head moves only when
/// you `prepend`, so reaching a wrapped buffer means constructing it on purpose.
/// That is what a space is for — its cases are defined rather than produced.
///
/// Modelled on `withEveryDeque(ofCapacities:)` in swift-collections' own test
/// support, which is where the idea came from.
public enum DequeLayouts {

    /// Every `(capacity, prepended, appended)` arrangement, smallest deque
    /// first.
    ///
    /// Contents are always `0 ..< count`, so two layouts of the same count are
    /// equal *as values* and differ only in where the buffer's head sits. That
    /// is the point: the laws are about behaviour, and behaviour is what should
    /// not depend on the head's position.
    ///
    /// Size is the element count, so a failure is reported at the smallest deque
    /// that exhibits it.
    public static func everyLayout(
        _ label: String = "deque",
        ofCapacities capacities: [Int] = [0, 1, 2, 3, 5, 10]
    ) -> Enumeration<Deque<Int>> {
        var built: [Deque<Int>] = []
        for capacity in capacities.sorted() {
            for total in 0 ... capacity {
                for prepended in 0 ... total {
                    built.append(layout(capacity: capacity, prepended: prepended, total: total))
                }
            }
        }
        return Every.elements(label, in: built, size: { $0.count })
    }

    /// Build one arrangement. `prepend` walks the head backwards through the
    /// buffer and `append` fills forwards from it, so `prepended` is the dial
    /// that moves the head — and the wrap.
    private static func layout(capacity: Int, prepended: Int, total: Int) -> Deque<Int> {
        var deque = Deque<Int>()
        deque.reserveCapacity(capacity)
        for value in stride(from: prepended - 1, through: 0, by: -1) {
            deque.prepend(value)
        }
        for value in prepended ..< total {
            deque.append(value)
        }
        return deque
    }
}
