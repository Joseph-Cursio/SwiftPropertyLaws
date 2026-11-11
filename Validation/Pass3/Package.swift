// swift-tools-version: 6.1
import PackageDescription

/// Validation harness, Pass 3 (PRD §8): git archaeology against
/// `swift-collections`. `Validation/FINDINGS.md` has the write-up.
///
/// `swift-collections` is pinned to revision `8e5e4a8f`, the parent of
/// `35349601`, which fixed `_Bitmap.symmetricDifference` to use `^` instead
/// of `&`. The bug turned out to be dead code: `TreeSet<Int>` passes every
/// SetAlgebra law at that SHA, and `ValidationPass3Tests` asserts exactly
/// that.
///
/// **This is its own package because of that pin.** The revision's manifest
/// conditions a build setting on a trait it never declares, which Swift
/// 6.4's package manager rejects. A pin applies to the whole package that
/// declares it, so while Pass 3 shared a package with Pass 2, neither built
/// on 6.4. Run it with Swift 6.3.3 and the Command Line Tools' 26.5 SDK:
///
///   cd Validation/Pass3
///   SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swiftly run swift test +6.3.3
let package = Package(
    name: "ValidationPass3",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(name: "SwiftPropertyLaws", path: "../.."),
        // Pin to the parent of 35349601 — the buggy SHA where
        // `_Bitmap.symmetricDifference` used `&` (intersection) instead
        // of `^` (xor). DO NOT update without re-validating Pass 3: the
        // test records what the kit reports at this exact revision.
        .package(
            url: "https://github.com/apple/swift-collections.git",
            revision: "8e5e4a8f3617283b556064574651fc0869943c9a"
        )
    ],
    targets: [
        .testTarget(
            name: "ValidationPass3Tests",
            dependencies: [
                .product(name: "PropertyLawKit", package: "SwiftPropertyLaws"),
                .product(name: "HashTreeCollections", package: "swift-collections")
            ]
        )
    ]
)
