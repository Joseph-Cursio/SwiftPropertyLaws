import PropertyBased // swiftlint:disable:this unused_import - used by the @PropertyLawSuite expansion
import PropertyLawKit // swiftlint:disable:this unused_import - used by the @PropertyLawSuite expansion
import PropertyLawMacro
import Testing // swiftlint:disable:this unused_import - used by the @PropertyLawSuite expansion

/// A nested generator, proved by compiling. The `dimmed` case's payload is
/// rendered by `MemberwiseEmitter` as a `zip(...)` with its `.map` on the next
/// line, inside the `Gen.oneOf(` list, and the test stub then moves every
/// continuation line under `using:` (`ExpressionLayout`). The goldens pin that
/// text; only the compiler can say the layout is still Swift. The emitted
/// `@Test`s running clean say the laws hold over what the generator draws,
/// not that it draws both cases: one that drew only `.off` would fail only the
/// Heuristic `Hashable.distribution`, which records a warning rather than a
/// failure on Swift 6.3 and later.
@PropertyLawSuite
// swiftlint:disable:next unused_declaration - referenced only by the @PropertyLawSuite expansion
enum EndToEndSignal: Equatable, Hashable, Sendable {
    case off
    case dimmed(level: Int, warm: Bool)
}
