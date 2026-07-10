// swift-tools-version: 6.1
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "SwiftPropertyLaws",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .tvOS(.v17),
        .watchOS(.v10),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "PropertyLawKit",
            targets: ["PropertyLawKit"]
        ),
        .library(
            name: "PropertyLawMacro",
            targets: ["PropertyLawMacro"]
        ),
        // PRD §5.7 generator-derivation strategist exposed as its own
        // shipped library so downstream tools (SwiftInferProperties M3+,
        // per its PRD §11) call into the shared priority order rather than
        // reimplementing it. The module's public surface is just the
        // strategist + its input/output value types — `KnownProtocol` and
        // `MemberwiseEmitter` stay `package`-scoped for now (M1 of the
        // SwiftInferProperties cross-validation work doesn't need either).
        .library(
            name: "PropertyLawCore",
            targets: ["PropertyLawCore"]
        ),
        // v2.1.0 — Complex<RealType> generator helpers carved out as an
        // opt-in product so the main `PropertyLawKit` line keeps a zero
        // `swift-numerics` footprint. Consumers that need
        // `Gen<Complex<Double>>.edgeCaseBiased()` (SwiftInferProperties'
        // v1.42+ Phase-1 test-execution verify mode is the first) `import
        // PropertyLawComplex` explicitly.
        .library(
            name: "PropertyLawComplex",
            targets: ["PropertyLawComplex"]
        ),
        // Phase 1 M0 of the collections/async workplan — swift-collections
        // law coverage carved out as an opt-in product (same posture as
        // `PropertyLawComplex`) so the main `PropertyLawKit` line keeps a
        // zero `swift-collections` footprint. M0 ships scaffolding + the
        // conformance audit; generators and law wiring land in M1+.
        .library(
            name: "PropertyLawCollections",
            targets: ["PropertyLawCollections"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/x-sheep/swift-property-based.git", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "602.0.0"),
        // Optional kit-side dep — used only by the `PropertyLawComplex`
        // target. The main `PropertyLawKit` line does not depend on it.
        .package(url: "https://github.com/apple/swift-numerics.git", from: "1.0.0"),
        // Optional kit-side dep — used only by the `PropertyLawCollections`
        // target. The main `PropertyLawKit` line does not depend on it.
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.2.0")
        // `swift-property-based` is the single property-based backend.
        // The PRD §4.5 `PropertyBackend` abstraction stays public — its
        // closure-level seam is non-leaky, and a future second backend can
        // drop in without protocol changes — but v1 deliberately ships a
        // single best-of-breed implementation rather than chasing parity
        // for its own sake.
    ],
    targets: [
        .target(
            name: "PropertyLawKit",
            dependencies: [
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        ),
        .testTarget(
            name: "PropertyLawKitTests",
            dependencies: [
                "PropertyLawKit",
                .product(name: "PropertyBased", package: "swift-property-based")
            ]
        ),

        // Shared core target. The §5.7 generator-derivation strategist is
        // exposed publicly via the `PropertyLawCore` product (added v1.6.0)
        // for downstream consumption by SwiftInferProperties M3+. The
        // PRD §4.3 `KnownProtocol` enum and the `MemberwiseEmitter`
        // text-renderer stay `package`-scoped — they're consumed only by
        // `PropertyLawMacroImpl` and `PropertyLawDiscoveryTool` inside this
        // package and aren't part of the shipped API contract.
        .target(
            name: "PropertyLawCore",
            dependencies: []
        ),
        .testTarget(
            name: "PropertyLawCoreTests",
            dependencies: ["PropertyLawCore"]
        ),
        // Shared SwiftSyntax helpers consumed by both the macro impl and the
        // discovery plugin. Leaf target depending only on PropertyLawCore +
        // SwiftSyntax (the parsing lib both already link) — deliberately not
        // SwiftCompilerPlugin/SwiftSyntaxMacros, so the discovery plugin keeps
        // its independence from PropertyLawMacroImpl (PRD §9 Decision 4) while
        // the `MemberBlockInspector` logic lives in exactly one place.
        .target(
            name: "PropertyLawSyntaxSupport",
            dependencies: [
                "PropertyLawCore",
                .product(name: "SwiftSyntax", package: "swift-syntax")
            ]
        ),
        // User-facing macro target — declarations only. Re-exports
        // PropertyLawKit so users importing PropertyLawMacro can call the
        // generated `checkXxxPropertyLaws` functions without a second import.
        .target(
            name: "PropertyLawMacro",
            dependencies: [
                "PropertyLawKit",
                "PropertyLawMacroImpl"
            ]
        ),
        // Compiler-plugin target hosting the macro implementation. Plugin
        // targets compile against swift-syntax and run during macro expansion.
        .macro(
            name: "PropertyLawMacroImpl",
            dependencies: [
                "PropertyLawCore",
                "PropertyLawSyntaxSupport",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax")
            ]
        ),
        .testTarget(
            name: "PropertyLawMacroTests",
            dependencies: [
                "PropertyLawMacro",
                "PropertyLawMacroImpl",
                "PropertyLawKit",
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),

        // Whole-module discovery (PRD §5.3) — the cross-file form M1's
        // peer macro can't implement, delivered as a CommandPlugin that
        // walks all `.swift` files in a target and emits a generated test
        // file. The plugin is intentionally thin; the executable tool
        // does the actual SwiftSyntax work.
        .executableTarget(
            name: "PropertyLawDiscoveryTool",
            dependencies: [
                "PropertyLawCore",
                "PropertyLawSyntaxSupport",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),
        .plugin(
            name: "PropertyLawDiscoveryPlugin",
            capability: .command(
                intent: .custom(
                    verb: "propertylawcheck",
                    description: """
                        Generate PropertyLawKit test files by walking a target's source files \
                        and detecting stdlib protocol conformances.
                        """
                ),
                permissions: [
                    .writeToPackageDirectory(reason:
                        "PropertyLawDiscoveryPlugin writes a generated test file (default: " +
                        "Tests/<Target>Tests/PropertyLawTests.generated.swift) listing the " +
                        "checkXxxPropertyLaws calls for each detected conformance."
                    )
                ]
            ),
            dependencies: [
                "PropertyLawDiscoveryTool"
            ]
        ),
        .testTarget(
            name: "PropertyLawDiscoveryToolTests",
            dependencies: [
                "PropertyLawDiscoveryTool",
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftParser", package: "swift-syntax")
            ]
        ),

        // v2.1.0 — opt-in Complex<RealType> generator helpers. Lives in
        // its own product so `swift-numerics` stays out of the main
        // `PropertyLawKit` transitive dependency set. Depends on
        // `PropertyBased` for `Gen<T>` / `Generator<Value, Shrinker>` and
        // on `ComplexModule` for `Complex<Double>` itself.
        .target(
            name: "PropertyLawComplex",
            dependencies: [
                .product(name: "PropertyBased", package: "swift-property-based"),
                // `ComplexModule` brings `Complex<RealType>`; `RealModule`
                // brings `Double: Real`, which `Complex<Double>` requires.
                .product(name: "ComplexModule", package: "swift-numerics"),
                .product(name: "RealModule", package: "swift-numerics")
            ]
        ),
        .testTarget(
            name: "PropertyLawComplexTests",
            dependencies: [
                "PropertyLawComplex",
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "ComplexModule", package: "swift-numerics"),
                .product(name: "RealModule", package: "swift-numerics")
            ]
        ),

        // Collections/async workplan Phase 1 — opt-in swift-collections law
        // coverage. Lives in its own product so `swift-collections` stays out
        // of the main `PropertyLawKit` transitive dependency set (the
        // `PropertyLawComplex` precedent). Depends on the five per-module
        // products rather than the `Collections` umbrella so each type's
        // module lineage stays explicit.
        .target(
            name: "PropertyLawCollections",
            dependencies: [
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "HeapModule", package: "swift-collections"),
                .product(name: "BitCollections", package: "swift-collections"),
                .product(name: "HashTreeCollections", package: "swift-collections")
            ]
        ),
        .testTarget(
            name: "PropertyLawCollectionsTests",
            dependencies: [
                "PropertyLawCollections",
                "PropertyLawKit",
                .product(name: "PropertyBased", package: "swift-property-based"),
                .product(name: "DequeModule", package: "swift-collections"),
                .product(name: "OrderedCollections", package: "swift-collections"),
                .product(name: "HeapModule", package: "swift-collections"),
                .product(name: "BitCollections", package: "swift-collections"),
                .product(name: "HashTreeCollections", package: "swift-collections")
            ]
        )
    ]
)
