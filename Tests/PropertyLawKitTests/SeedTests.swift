@testable import PropertyLawKit
import Testing

struct SeedTests {

    @Test func roundTripsThroughBase64() throws {
        let original = Seed(stateA: 12_345, stateB: 67_890, stateC: 11_111, stateD: 22_222)
        let base64 = original.description
        let restored = try #require(Seed(base64: base64))
        #expect(restored == original)
    }

    @Test func returnsNilForInvalidBase64() {
        #expect(Seed(base64: "not-valid-base64!!!") == nil)
    }

    @Test func equalStateProducesEqualSeeds() {
        let lhs = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let rhs = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        #expect(lhs == rhs)
    }

    @Test func hashableTreatsEqualStateAsOneEntry() {
        let dupOne = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let dupTwo = Seed(stateA: 1, stateB: 2, stateC: 3, stateD: 4)
        let other = Seed(stateA: 5, stateB: 6, stateC: 7, stateD: 8)
        let unique: Set<Seed> = [dupOne, dupTwo, other]
        #expect(unique.count == 2)
    }
}
