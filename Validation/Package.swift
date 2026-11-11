// swift-tools-version: 6.1
import PackageDescription

/// Validation harness, Pass 2 (PRD §8): wires `PropertyLawKit` against
/// external Swift packages and runs actual law checks. Lives in its own
/// SwiftPM package so the external deps don't leak into the kit's main
/// manifest — consumers of SwiftPropertyLaws never see ArgumentParser,
/// BigInt or swift-numerics.
///
/// Run with:
///   cd Validation && swift test
///
/// **Pass 2** (`ValidationPass2Tests`) — exercises the kit against public
/// types from `swift-argument-parser`, `BigInt`, `swift-numerics`,
/// Foundation and the standard library. Demonstrates the pipeline composes:
/// kit + external SwiftPM dep + generators + assertions all link and run
/// end-to-end.
///
/// **Pass 3** is a separate package, `Validation/Pass3`. It pins
/// `swift-collections` to a revision whose manifest Swift 6.4's package
/// manager rejects, and a pin applies to every target of the package that
/// declares it, so keeping it here would stop Pass 2 building on 6.4.
let package = Package(
    name: "Validation",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "SwiftPropertyLaws", path: ".."),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.0"),
        // attaswift/BigInt — arbitrary-precision integers conforming to
        // BinaryInteger / SignedInteger / UnsignedInteger / Numeric. v1.4
        // M2's exact-arithmetic algebraic laws should hold cleanly here;
        // first ever property-based test of BigInt's protocol conformance.
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.5.0"),
        // apple/swift-numerics — exposes Complex<RealType> conforming to
        // Numeric / SignedNumeric. Complex<Double> multiplication is
        // non-associative under exact equality due to IEEE-754 rounding;
        // tests document that boundary explicitly.
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0")
    ],
    targets: [
        .testTarget(
            name: "ValidationPass2Tests",
            dependencies: [
                // PropertyLawKit re-exports PropertyBased (`@_exported import`),
                // so a direct dep on it isn't needed here.
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "ComplexModule", package: "swift-numerics")
            ]
        )
    ]
)
