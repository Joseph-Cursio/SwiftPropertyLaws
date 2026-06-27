import Foundation
import Testing
@testable import PropertyLawDiscoveryTool
@testable import PropertyLawCore

// One scenario per recognized conformance shape; the suite legitimately
// grows past SwiftLint's default body-length threshold as new protocols
// ship. Paired with an explicit re-enable at end of file.
// swiftlint:disable type_body_length file_length

struct ModuleScannerTests {

    // MARK: - Single-file conformances

    @Test func detectsStructConformances() throws {
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo: Equatable, Hashable {
                    let value: Int
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        let entry = map.entries[0]
        #expect(entry.typeName == "Foo")
        #expect(entry.conformances == [.hashable])  // most-specific dedupe
        #expect(entry.provenances.count == 1)
        #expect(entry.provenances[0].kind == .primary)
        #expect(entry.provenances[0].line == 1)
    }

    // MARK: - Tier 6: initializer-based derivation (extraction end-to-end)

    @Test func derivesStructThroughUserInitializer() throws {
        let dir = try makeFixtureDir([
            "Money.swift": """
                struct Money: Equatable {
                    let cents: Int
                    init(cents: Int) { self.cents = cents }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        guard case .initializerBased(let arguments) = map.entries[0].derivationStrategy else {
            Issue.record("expected initializerBased; got \(map.entries[0].derivationStrategy)")
            return
        }
        #expect(arguments.count == 1)
        #expect(arguments[0].label == "cents")
        #expect(arguments[0].generatorExpression == "Gen<Int>.int()")
    }

    @Test func scanResolvesNestedCustomTypeMember() throws {
        let dir = try makeFixtureDir([
            "Models.swift": """
                struct Customer: Equatable { let name: String }
                struct Order: Equatable {
                    let id: Int
                    let customer: Customer
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let order = try #require(map.entries.first { $0.typeName == "Order" })
        guard case .memberwiseArbitrary = order.derivationStrategy else {
            Issue.record("expected Order to derive via nested resolution; got \(order.derivationStrategy)")
            return
        }
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Order",
            strategy: order.derivationStrategy
        )
        #expect(expression.contains("Customer(name: $0)"))
    }

    @Test func scanDerivesPayloadEnumWithOneOf() throws {
        let dir = try makeFixtureDir([
            "Shape.swift": """
                enum Shape: Equatable {
                    case empty
                    case circle(radius: Int)
                    case rect(width: Int, height: Int)
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let shape = try #require(map.entries.first { $0.typeName == "Shape" })
        guard case .enumCases(let cases) = shape.derivationStrategy else {
            Issue.record("expected enumCases; got \(shape.derivationStrategy)")
            return
        }
        #expect(cases.count == 3)
        let expression = GeneratorExpressionEmitter.expression(
            typeName: "Shape",
            strategy: shape.derivationStrategy
        )
        #expect(expression.contains("Gen.oneOf("))
        #expect(expression.contains("Gen.always(Shape.empty)"))
        #expect(expression.contains("Shape.circle(radius: $0)"))
    }

    @Test func failableInitializerDeclinesToTodoInScan() throws {
        let dir = try makeFixtureDir([
            "Code.swift": """
                struct Code: Equatable {
                    let raw: String
                    init?(raw: String) { self.raw = raw }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        guard case .todo = map.entries[0].derivationStrategy else {
            Issue.record("expected .todo for a failable-only initializer")
            return
        }
    }

    @Test func detectsEnumConformances() throws {
        let dir = try makeFixtureDir([
            "Direction.swift": """
                enum Direction: String, Codable, CaseIterable {
                    case north, south
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.codable])
    }

    // MARK: - Cross-file extension aggregation (the M2 unlock)

    @Test func aggregatesExtensionsAcrossFiles() throws {
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo {
                    let value: Int
                }
                """,
            "Foo+Equatable.swift": """
                extension Foo: Equatable {
                    static func == (lhs: Foo, rhs: Foo) -> Bool { lhs.value == rhs.value }
                }
                """,
            "Foo+Hashable.swift": """
                extension Foo: Hashable {
                    func hash(into hasher: inout Hasher) { hasher.combine(value) }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        let entry = map.entries[0]
        #expect(entry.typeName == "Foo")
        #expect(entry.conformances == [.hashable])
        #expect(entry.provenances.count == 3)  // primary + two extensions
        // Sorted: file paths first, then line.
        #expect(entry.provenances.contains { $0.kind == .primary })
        let extensionCount = entry.provenances.filter { $0.kind == .extension }.count
        #expect(extensionCount == 2)
    }

    @Test func conditionalConformanceExtensionsAreSkipped() throws {
        // PRD §4.4: conditional conformances (`extension Foo: Equatable
        // where T: Equatable`) aren't unconditional — emitting an
        // unconditional check would be wrong. M3 handles via
        // @LawGenerator(bindings:).
        let dir = try makeFixtureDir([
            "Container.swift": """
                struct Container<T> {
                    let item: T
                }
                """,
            "Container+Conditional.swift": """
                extension Container: Equatable where T: Equatable {
                    static func == (lhs: Container, rhs: Container) -> Bool { false }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        // Primary decl recorded (no inheritance), conditional extension
        // skipped → no recognized conformances.
        #expect(map.entries[0].conformances == [])
    }

    // MARK: - Multiple types

    @Test func multipleTypesYieldMultipleEntries() throws {
        let dir = try makeFixtureDir([
            "Types.swift": """
                struct Foo: Equatable {
                    let value: Int
                }
                struct Bar: Hashable {
                    let other: Int
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 2)
        // Sorted alphabetically.
        #expect(map.entries[0].typeName == "Bar")
        #expect(map.entries[0].conformances == [.hashable])
        #expect(map.entries[1].typeName == "Foo")
        #expect(map.entries[1].conformances == [.equatable])
    }

    // MARK: - Encodable + Decodable pairing

    @Test func encodableDecodablePairResolvesToCodable() throws {
        let dir = try makeFixtureDir([
            "Record.swift": """
                struct Record: Encodable, Decodable {
                    let id: Int
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.codable])
    }

    // MARK: - Unemittable protocol filter

    @Test func iteratorProtocolOnlyFiltersToEmptyConformances() throws {
        let dir = try makeFixtureDir([
            "Cursor.swift": """
                struct Cursor: IteratorProtocol {
                    mutating func next() -> Int? { nil }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [])
    }

    @Test func caseIterableOnlyFiltersToEmptyConformances() throws {
        // CaseIterable is unemittable; on its own it leaves nothing for
        // the macro/plugin to emit. Users call checkCaseIterablePropertyLaws
        // manually if they want the law check.
        let dir = try makeFixtureDir([
            "Direction.swift": """
                enum Direction: CaseIterable {
                    case north, south
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [])
    }

    // MARK: - v1.8 kit-defined algebraic protocols

    @Test func bareSemigroupSurvivesScan() throws {
        let dir = try makeFixtureDir([
            "Counter.swift": """
                struct Counter: Semigroup {
                    let value: Int
                    static func combine(_ lhs: Counter, _ rhs: Counter) -> Counter {
                        Counter(value: lhs.value + rhs.value)
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.semigroup])
    }

    @Test func monoidSubsumesSemigroupAfterScan() throws {
        // Most-specific dedupe collapses `: Semigroup, Monoid` to just
        // `[.monoid]` — checkMonoidPropertyLaws auto-runs Semigroup's
        // combineAssociativity via .all.
        let dir = try makeFixtureDir([
            "Tally.swift": """
                struct Tally: Semigroup, Monoid {
                    let value: Int
                    static let identity = Tally(value: 0)
                    static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
                        Tally(value: lhs.value + rhs.value)
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.monoid])
    }

    @Test func bareMonoidConformanceSurvivesScan() throws {
        let dir = try makeFixtureDir([
            "Tally.swift": """
                struct Tally: Monoid {
                    let value: Int
                    static let identity = Tally(value: 0)
                    static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
                        Tally(value: lhs.value + rhs.value)
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.monoid])
    }

    // MARK: - v1.9 kit-defined CommutativeMonoid / Group / Semilattice

    @Test func commutativeMonoidSubsumesMonoidChainAfterScan() throws {
        // Most-specific dedupe collapses the full chain to just
        // `[.commutativeMonoid]` — checkCommutativeMonoidPropertyLaws
        // auto-runs Monoid's identity laws and Semigroup's
        // combineAssociativity via .all.
        let dir = try makeFixtureDir([
            "Tally.swift": """
                struct Tally: Semigroup, Monoid, CommutativeMonoid {
                    let value: Int
                    static let identity = Tally(value: 0)
                    static func combine(_ lhs: Tally, _ rhs: Tally) -> Tally {
                        Tally(value: lhs.value + rhs.value)
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.commutativeMonoid])
    }

    @Test func groupSubsumesMonoidAfterScan() throws {
        // Group refines Monoid; CommutativeMonoid is NOT subsumed (non-
        // commutative groups are valid). `: Monoid, Group` reduces to
        // `[.group]`.
        let dir = try makeFixtureDir([
            "AdditiveInt.swift": """
                struct AdditiveInt: Monoid, Group {
                    let value: Int
                    static let identity = AdditiveInt(value: 0)
                    static func combine(
                        _ lhs: AdditiveInt, _ rhs: AdditiveInt
                    ) -> AdditiveInt {
                        AdditiveInt(value: lhs.value + rhs.value)
                    }
                    static func inverse(_ x: AdditiveInt) -> AdditiveInt {
                        AdditiveInt(value: -x.value)
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.group])
    }

    @Test func commutativeMonoidPlusGroupBothSurviveScan() throws {
        // Incomparable arms — both surface in the conformance set.
        let dir = try makeFixtureDir([
            "AdditiveInt.swift": """
                struct AdditiveInt: CommutativeMonoid, Group {
                    let value: Int
                    static let identity = AdditiveInt(value: 0)
                    static func combine(
                        _ lhs: AdditiveInt, _ rhs: AdditiveInt
                    ) -> AdditiveInt {
                        AdditiveInt(value: lhs.value + rhs.value)
                    }
                    static func inverse(_ x: AdditiveInt) -> AdditiveInt {
                        AdditiveInt(value: -x.value)
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.commutativeMonoid, .group])
    }

    @Test func semilatticeSubsumesCommutativeMonoidChainAfterScan() throws {
        // Semilattice refines CommutativeMonoid; full chain reduces to
        // `[.semilattice]`.
        let dir = try makeFixtureDir([
            "MaxInt.swift": """
                struct MaxInt: Semigroup, Monoid, CommutativeMonoid, Semilattice {
                    let value: Int
                    static let identity = MaxInt(value: .min)
                    static func combine(_ lhs: MaxInt, _ rhs: MaxInt) -> MaxInt {
                        MaxInt(value: max(lhs.value, rhs.value))
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.semilattice])
    }

    @Test func bareSemilatticeConformanceSurvivesScan() throws {
        let dir = try makeFixtureDir([
            "MaxInt.swift": """
                struct MaxInt: Semilattice {
                    let value: Int
                    static let identity = MaxInt(value: .min)
                    static func combine(_ lhs: MaxInt, _ rhs: MaxInt) -> MaxInt {
                        MaxInt(value: max(lhs.value, rhs.value))
                    }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.semilattice])
    }

    @Test func strideableOnlyEmitsAsComparable() throws {
        // Strideable's check function takes an extra `strideGenerator:` arg
        // the scanner can't synthesize, so Strideable is filtered from
        // emit. But Strideable refines Comparable in stdlib — `set(from:)`
        // auto-adds Comparable, surviving the filter.
        let dir = try makeFixtureDir([
            "Step.swift": """
                struct Step: Strideable {
                    let value: Int
                    static func < (lhs: Step, rhs: Step) -> Bool { lhs.value < rhs.value }
                    func distance(to other: Step) -> Int { other.value - value }
                    func advanced(by step: Int) -> Step { Step(value: value + step) }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        try #require(map.entries.count == 1)
        #expect(map.entries[0].conformances == [.comparable])
    }

    // MARK: - Idempotence

    @Test func sortedFileOrderProducesDeterministicOutput() throws {
        let dir = try makeFixtureDir([
            "z.swift": "struct Last: Equatable { let v: Int }",
            "a.swift": "struct First: Equatable { let v: Int }"
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let paths = filePaths(in: dir)
        // Scan twice with shuffled and sorted inputs — output should match.
        let sortedScan = ModuleScanner.scan(sourceFiles: paths.sorted())
        let reversedScan = ModuleScanner.scan(sourceFiles: paths.sorted().reversed())
        #expect(sortedScan == reversedScan)
    }

    // MARK: - Error tolerance

    @Test func unreadableFileSurfacesAsParseFailureNotFatal() throws {
        let map = ModuleScanner.scan(sourceFiles: ["/nonexistent/path/Foo.swift"])
        #expect(map.entries.isEmpty)
        try #require(map.parseFailures.count == 1)
        #expect(map.parseFailures.first?.filePath == "/nonexistent/path/Foo.swift")
    }

    // MARK: - PRD §5.4 witness recording (M4)

    @Test func recordsWitnessesFromPrimaryDeclaration() throws {
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo {
                    static func == (lhs: Foo, rhs: Foo) -> Bool { true }
                    static func < (lhs: Foo, rhs: Foo) -> Bool { false }
                    func hash(into hasher: inout Hasher) {}
                    func encode(to encoder: Encoder) throws {}
                    init(from decoder: Decoder) throws {}
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let witnesses = try #require(map.witnesses["Foo"])
        #expect(witnesses.hasEqualEqualOperator)
        #expect(witnesses.hasLessThanOperator)
        #expect(witnesses.hasHashIntoMethod)
        #expect(witnesses.hasEncodeToMethod)
        #expect(witnesses.hasInitFromInitializer)
    }

    @Test func aggregatesWitnessesAcrossExtensions() throws {
        // Witnesses defined in multiple extensions across files must
        // OR-merge into a single per-type WitnessSet — same aggregation
        // contract as inheritance names.
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo {}
                """,
            "Foo+Equatable.swift": """
                extension Foo {
                    static func == (lhs: Foo, rhs: Foo) -> Bool { true }
                }
                """,
            "Foo+Hashable.swift": """
                extension Foo {
                    func hash(into hasher: inout Hasher) {}
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        let witnesses = try #require(map.witnesses["Foo"])
        #expect(witnesses.hasEqualEqualOperator)
        #expect(witnesses.hasHashIntoMethod)
        // Sanity: didn't pick up things that weren't there.
        #expect(witnesses.hasLessThanOperator == false)
        #expect(witnesses.hasEncodeToMethod == false)
    }

    @Test func witnessesAreEmptyForTypeWithoutDetectableSignatures() throws {
        // PRD §5.4 detectors are conservative — a type with non-witness
        // members should not appear in `witnesses` at all (the scanner
        // omits empty WitnessSets to keep dictionary keys meaningful).
        let dir = try makeFixtureDir([
            "Plain.swift": """
                struct Plain {
                    let value: Int
                    func describe() -> String { "" }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        #expect(map.witnesses["Plain"] == nil)
    }

    @Test func nonStaticEqualOperatorDoesNotCountAsEquatableWitness() throws {
        // Free-function operator overloads are valid Swift but not the
        // form we treat as a HIGH-confidence Equatable witness — the
        // §5.4 quality bar pushes toward the static-method-in-type form.
        let dir = try makeFixtureDir([
            "Foo.swift": """
                struct Foo {
                    func equals(_ other: Foo) -> Bool { false }
                }
                """
        ])
        defer { try? FileManager.default.removeItem(atPath: dir) }

        let map = ModuleScanner.scan(sourceFiles: filePaths(in: dir))
        // No witnesses → key absent from the dictionary.
        #expect(map.witnesses["Foo"] == nil)
    }

    // MARK: - Helpers

    private func makeFixtureDir(_ files: [String: String]) throws -> String {
        let dir = NSTemporaryDirectory().appending("PropertyLawScan-\(UUID().uuidString)/")
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        for (name, contents) in files {
            try contents.write(
                toFile: dir + name,
                atomically: true,
                encoding: .utf8
            )
        }
        return dir
    }

    private func filePaths(in dir: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: dir).map { dir + $0 }) ?? []
    }
}

// swiftlint:enable type_body_length file_length
