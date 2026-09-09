import Testing
import PropertyBased
@testable import PropertyLawKit

struct ReplayValidationTests {

    // MARK: - Pass-through when no expected env supplied

    @Test func nilExpectedEnvIsAlwaysAllowed() async throws {
        try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: LawCheckOptions(budget: .sanity)
        )
    }

    // MARK: - Exact-match policy

    @Test func exactMatchAllowsCurrentEnvironment() async throws {
        let options = LawCheckOptions(
            budget: .sanity,
            expectedReplayEnvironment: Environment.current
        )
        try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: options
        )
    }

    @Test func exactMatchRejectsSwiftVersionDrift() async throws {
        let stale = Environment(
            swiftVersion: "1.0",
            backendIdentity: SwiftPropertyBasedBackend().identifier,
            generatorSchemaHash: "m1-no-registry"
        )
        let options = LawCheckOptions(
            budget: .sanity,
            expectedReplayEnvironment: stale
        )
        await #expect(throws: ReplayEnvironmentMismatch.self) {
            try await checkEquatablePropertyLaws(
                for: Int.self,
                using: TestGen.smallInt(),
                options: options
            )
        }
    }

    @Test func exactMatchRejectsBackendDrift() async throws {
        let staleBackendEnv = Environment(
            swiftVersion: Environment.current.swiftVersion,
            backendIdentity: "imaginary-backend",
            generatorSchemaHash: Environment.current.generatorSchemaHash
        )
        let options = LawCheckOptions(
            budget: .sanity,
            expectedReplayEnvironment: staleBackendEnv
        )
        let mismatch = await #expect(throws: ReplayEnvironmentMismatch.self) {
            try await checkEquatablePropertyLaws(
                for: Int.self,
                using: TestGen.smallInt(),
                options: options
            )
        }
        #expect(mismatch?.expected.backendIdentity == "imaginary-backend")
        #expect(mismatch?.actual.backendIdentity == SwiftPropertyBasedBackend().identifier)
    }

    // MARK: - Relaxation policies

    @Test func matchBackendOnlyIgnoresSwiftVersion() async throws {
        let staleVersionEnv = Environment(
            swiftVersion: "1.0",
            backendIdentity: SwiftPropertyBasedBackend().identifier,
            generatorSchemaHash: Environment.current.generatorSchemaHash
        )
        let options = LawCheckOptions(
            budget: .sanity,
            expectedReplayEnvironment: staleVersionEnv,
            replayRelaxation: .matchBackendOnly
        )
        try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: options
        )
    }

    @Test func matchSwiftVersionOnlyIgnoresBackendDrift() async throws {
        let staleBackendEnv = Environment(
            swiftVersion: Environment.current.swiftVersion,
            backendIdentity: "imaginary-backend",
            generatorSchemaHash: Environment.current.generatorSchemaHash
        )
        let options = LawCheckOptions(
            budget: .sanity,
            expectedReplayEnvironment: staleBackendEnv,
            replayRelaxation: .matchSwiftVersionOnly
        )
        try await checkEquatablePropertyLaws(
            for: Int.self,
            using: TestGen.smallInt(),
            options: options
        )
    }

    // MARK: - Validation runs at every public entry point

    @Test func hashableEntryPointVerifiesEnvironment() async throws {
        let stale = Environment(
            swiftVersion: "1.0",
            backendIdentity: SwiftPropertyBasedBackend().identifier,
            generatorSchemaHash: Environment.current.generatorSchemaHash
        )
        await #expect(throws: ReplayEnvironmentMismatch.self) {
            try await checkHashablePropertyLaws(
                for: Int.self,
                using: TestGen.smallInt(),
                options: LawCheckOptions(budget: .sanity, expectedReplayEnvironment: stale)
            )
        }
    }

    @Test func collectionEntryPointVerifiesEnvironment() async throws {
        let stale = Environment(
            swiftVersion: "1.0",
            backendIdentity: SwiftPropertyBasedBackend().identifier,
            generatorSchemaHash: Environment.current.generatorSchemaHash
        )
        await #expect(throws: ReplayEnvironmentMismatch.self) {
            try await checkCollectionPropertyLaws(
                for: [Int].self,
                using: TestGen.smallInt().array(of: 0...4),
                options: LawCheckOptions(budget: .sanity, expectedReplayEnvironment: stale)
            )
        }
    }

    // MARK: - Diagnostic content

    @Test func mismatchDescriptionEnumeratesDivergingFields() {
        let expected = Environment(
            swiftVersion: "6.1",
            backendIdentity: "backend-a",
            generatorSchemaHash: "hash-a"
        )
        let actual = Environment(
            swiftVersion: "6.3",
            backendIdentity: "backend-b",
            generatorSchemaHash: "hash-a"
        )
        let mismatch = ReplayEnvironmentMismatch(expected: expected, actual: actual)
        let text = mismatch.description
        #expect(text.contains("swiftVersion: 6.1 → 6.3"))
        #expect(text.contains("backend: backend-a → backend-b"))
        // generatorSchemaHash matches so it should NOT appear in the diff list.
        #expect(text.contains("generatorSchema:") == false)
    }

    @Test func validationHappensBeforeAnyTrialBudget() async throws {
        // Sentinel: even with a generator that would otherwise be slow,
        // mismatched env throws before the trial loop. Use exhaustive budget
        // — if validation fired late we'd see hangs; firing early should be
        // instant.
        let stale = Environment(
            swiftVersion: "9.9",
            backendIdentity: SwiftPropertyBasedBackend().identifier,
            generatorSchemaHash: Environment.current.generatorSchemaHash
        )
        await #expect(throws: ReplayEnvironmentMismatch.self) {
            try await checkEquatablePropertyLaws(
                for: Int.self,
                using: TestGen.smallInt(),
                options: LawCheckOptions(
                    budget: .thorough,
                    expectedReplayEnvironment: stale
                )
            )
        }
    }
}
