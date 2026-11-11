@testable import PropertyLawKit
import Testing

/// Coverage suite for `ErrorBox` — the public Sendable wrapper around an
/// error description that backend authors construct when wrapping a thrown
/// error before crossing an actor boundary.
///
/// The kit's own law properties don't throw, so the bundled
/// `SwiftPropertyBasedBackend` has no `ErrorBox(_:)` call sites under
/// normal operation. Direct unit tests are the right shape — they exercise
/// the public API surface that downstream backend implementers depend on
/// without needing to plant a throwing-property fixture.
struct ErrorBoxTests {

    private struct Sample: Error, CustomStringConvertible {
        let description: String
    }

    @Test func wrappingErrorCapturesDescription() {
        let original = Sample(description: "boom")
        let box = ErrorBox(original)
        // CustomStringConvertible.description wins over Swift's default
        // type-name interpolation when the conformance is present.
        #expect(box.message == "boom")
    }

    @Test func wrappingErrorWithCustomDescriptionUsesItDirectly() {
        // Without conforming to CustomStringConvertible, Swift's default
        // string conversion produces a different format. We assert only
        // that ErrorBox stores *some* non-empty description, since the
        // exact format is a Swift runtime choice.
        struct Bare: Error {}
        let box = ErrorBox(Bare())
        #expect(box.message.isEmpty == false)
    }

    @Test func messageInitStoresVerbatim() {
        let box = ErrorBox(message: "connection refused")
        #expect(box.message == "connection refused")
    }

    @Test func errorBoxIsHashable() {
        let one = ErrorBox(message: "boom")
        let two = ErrorBox(message: "boom")
        let three = ErrorBox(message: "blast")
        #expect(one == two)
        #expect(one.hashValue == two.hashValue)
        #expect(one != three)

        let set: Set<ErrorBox> = [one, two, three]
        #expect(set.count == 2)
    }
}
