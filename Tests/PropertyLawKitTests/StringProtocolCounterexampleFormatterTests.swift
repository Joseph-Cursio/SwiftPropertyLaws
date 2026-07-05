import Testing
@testable import PropertyLawKit

/// Direct unit tests for the `StringProtocol` law counterexample formatters.
///
/// These diagnostic paths are unreachable through a real check run — `String`
/// and `Substring` are the only stdlib `StringProtocol` conformers and both
/// satisfy every law, and several laws (e.g. `stringInitRoundTrip`) reduce to
/// `String(x) == String(x)` and so cannot be violated by *any* conformer.
/// Testing the formatters directly is the only way to exercise the text they
/// render on failure. Passing `nil` for the `ErrorBox?` matches the unary-law
/// call site (the formatters ignore it).
struct StringProtocolFormatterTests {

    @Test func stringInitRoundTripFormatsSampleAndConversions() {
        let text = stringInitRoundTripCounterexample("hi", nil)
        #expect(text == "x = hi; String(x) = \"hi\"; String(String(x)) = \"hi\"")
    }

    @Test func countMatchesStringInitFormatsCounts() {
        let text = countMatchesStringInitCounterexample("abc", nil)
        #expect(text == "x = abc; x.count = 3, String(x).count = 3")
    }

    @Test func isEmptyMatchesCountZeroFormatsBothPredicates() {
        let text = isEmptyMatchesCountZeroCounterexample("", nil)
        #expect(text == "x = ; x.isEmpty = true, x.count == 0 = true")
    }

    @Test func hasPrefixEmptyFormatsResult() {
        let text = hasPrefixEmptyCounterexample("abc", nil)
        #expect(text == "x = abc; x.hasPrefix(empty) = true")
    }

    @Test func hasSuffixEmptyFormatsResult() {
        let text = hasSuffixEmptyCounterexample("abc", nil)
        #expect(text == "x = abc; x.hasSuffix(empty) = true")
    }

    @Test func lowercasedIdempotentFormatsBothApplications() {
        let text = lowercasedIdempotentCounterexample("AbC", nil)
        #expect(
            text == "x = AbC; x.lowercased() = \"abc\"; .lowercased().lowercased() = \"abc\""
        )
    }

    @Test func uppercasedIdempotentFormatsBothApplications() {
        let text = uppercasedIdempotentCounterexample("AbC", nil)
        #expect(
            text == "x = AbC; x.uppercased() = \"ABC\"; .uppercased().uppercased() = \"ABC\""
        )
    }

    @Test func utf8ViewInvarianceFormatsByteArrays() {
        let text = utf8ViewInvarianceCounterexample("AB", nil)
        #expect(text == "x = AB; x.utf8 = [65, 66]; String(x).utf8 = [65, 66]")
    }

    /// The formatters are generic over `StringProtocol` — exercise the
    /// `Substring` specialization too, not just `String`.
    @Test func formattersWorkOverSubstring() {
        let slice: Substring = "hello world".dropFirst(6)
        #expect(countMatchesStringInitCounterexample(slice, nil)
            == "x = world; x.count = 5, String(x).count = 5")
        #expect(hasPrefixEmptyCounterexample(slice, nil)
            == "x = world; x.hasPrefix(empty) = true")
    }
}
