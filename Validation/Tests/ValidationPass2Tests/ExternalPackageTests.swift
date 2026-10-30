import Testing
import ArgumentParser
import PropertyLawKit

/// Pass 2 validation (PRD §8): runs PropertyLawKit's `checkXxxPropertyLaws`
/// against public types from an external well-tested Swift package.
///
/// The bar PRD §8 sets is "find at least one real semantic conformance bug
/// in 5+ popular Swift packages before 1.0." This file isn't yet that — but
/// it proves the pipeline: kit + external package + generators + assertions
/// all compose at the SwiftPM level. Per-package coverage extends from here
/// when the §8 gate becomes the active priority.
///
/// Targets are public types from `swift-argument-parser` (1.6.0+):
/// - `ExitCode` — Int32-backed `Hashable` + `RawRepresentable` struct.
/// - `ArgumentVisibility` — three-static-instance `Hashable` struct.
/// - `CompletionShell` — closed-set String-backed `RawRepresentable` struct
///   with a failable `init?(rawValue:)` (zsh / bash / fish only).
///
/// All three are tiny but representative: a wrapper-around-a-primitive, a
/// closed-set state type, and a closed-set String-backed `RawRepresentable`.
/// If any of them harbored a hash/equality-consistency or round-trip bug,
/// the kit's Strict-tier checks would surface it.
struct ExternalPackageTests {

    /// `Hashable.distribution` asks what fraction of the draws produced distinct
    /// hash values, and fails below 10%. Over a domain of a few values that
    /// ratio is bounded by the domain's size rather than by the hash, so the
    /// law says nothing about these types and is skipped for them. Every
    /// Strict Hashable and Equatable law still runs.
    private static let hashDistribution = LawIdentifier(
        protocolName: "Hashable",
        lawName: "distribution"
    )

    // MARK: - ExitCode

    @Test func exitCodeHashableLawsHold() async throws {
        try await checkHashablePropertyLaws(
            for: ExitCode.self,
            using: Gen<ExitCode>.exitCode(),
            options: LawCheckOptions(
                budget: .standard,
                suppressions: [
                    .skip(
                        Self.hashDistribution,
                        reason: "the generator draws from ten fixed exit codes, "
                            + "so ten distinct hashes is the most there can be"
                    )
                ]
            )
        )
    }

    @Test func exitCodeRawRepresentableLawsHold() async throws {
        try await checkRawRepresentablePropertyLaws(
            for: ExitCode.self,
            using: Gen<ExitCode>.exitCode(),
            options: LawCheckOptions(budget: .standard)
        )
    }

    // MARK: - ArgumentVisibility

    @Test func argumentVisibilityHashableLawsHold() async throws {
        try await checkHashablePropertyLaws(
            for: ArgumentVisibility.self,
            using: Gen<ArgumentVisibility>.argumentVisibility(),
            options: LawCheckOptions(
                budget: .standard,
                suppressions: [
                    .skip(
                        Self.hashDistribution,
                        reason: "ArgumentVisibility has exactly three values, "
                            + "so three distinct hashes is the most there can be"
                    )
                ]
            )
        )
    }

    // MARK: - CompletionShell

    @Test func completionShellRawRepresentableLawsHold() async throws {
        try await checkRawRepresentablePropertyLaws(
            for: CompletionShell.self,
            using: Gen<CompletionShell>.completionShell(),
            options: LawCheckOptions(budget: .standard)
        )
    }
}

// MARK: - Generators

extension Gen where Value == ExitCode {
    /// Covers the wrapping-Int32 path with a fixed exit-code spread that
    /// includes negative, zero, and small/medium/large unsigned values.
    /// `Gen.element(of:)` returns an Optional; the `compactMap` unwraps
    /// it (the source array is non-empty so the wrap is always Some).
    static func exitCode() -> Generator<ExitCode, some SendableSequenceType> {
        Gen<Int?>.element(of: [-1, 0, 1, 2, 64, 65, 70, 127, 128, 255])
            .compactMap { $0 }
            .map { ExitCode(Int32($0)) }
    }
}

extension Gen where Value == ArgumentVisibility {
    /// Three-static-instance closed set — the documented public constants.
    /// `.element(of:)` picks uniformly across them.
    static func argumentVisibility() -> Generator<ArgumentVisibility, some SendableSequenceType> {
        let cases: [ArgumentVisibility] = [
            ArgumentVisibility.default,
            ArgumentVisibility.hidden,
            ArgumentVisibility.private
        ]
        return Gen<ArgumentVisibility?>.element(of: cases).compactMap { $0 }
    }
}

extension Gen where Value == CompletionShell {
    /// `CompletionShell.init?(rawValue:)` only succeeds for "zsh" / "bash" /
    /// "fish"; sample over the three documented public constants so every
    /// generated value round-trips.
    static func completionShell() -> Generator<CompletionShell, some SendableSequenceType> {
        let cases: [CompletionShell] = [.zsh, .bash, .fish]
        return Gen<CompletionShell?>.element(of: cases).compactMap { $0 }
    }
}
