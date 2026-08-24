import Testing
@testable import PropertyLawCore

/// **A module-qualified spelling is the type it names.** `Swift.String` is `String`.
///
/// `RawType(typeName:)` compared against `allCases.rawValue` exactly, and nothing anywhere in
/// this package stripped a module qualifier. So a member typed `Swift.String` matched no case,
/// its enclosing type became underivable, and the consumer reported an unsupported *carrier* — a
/// claim that the carrier is exotic, about a `String`.
///
/// **Hand-written Swift almost never writes `Swift.String`. Generated code writes nothing else**
/// — `swift-openapi-generator` fully-qualifies every type it emits, which is a large and growing
/// class of real Swift. Measured downstream on a generated client: **0 of 28 `codable-round-trip`
/// carriers had a resolvable member tree, against 16 of 28 once the spelling is recognised**, and
/// the subject went from 0 to 15 executing rows.
///
/// **The negative cases are the load-bearing ones**, because the hazard here is rewriting too
/// eagerly. A last-component rule would hand this table's `String` generator to a user's
/// `MyModule.String`, and would collapse `Components.Schemas.Response` to `Response`. Only
/// `Swift.` and `Foundation.` are stripped, only over a single dot, and — in the composite
/// parser — only when the remainder is a leaf this package already generates for.
struct ModuleQualifiedSpellingTests {

    // MARK: - RawType

    @Test func rawTypeRecognisesTheQualifiedSpelling() {
        #expect(RawType(typeName: "Swift.String") == .string)
        #expect(RawType(typeName: "Swift.Int") == .int)
        #expect(RawType(typeName: "Swift.Bool") == .bool)
        #expect(RawType(typeName: "Swift.UInt64") == .uint64)
    }

    @Test func rawTypeStillRecognisesTheBareSpelling() {
        #expect(RawType(typeName: "String") == .string)
        #expect(RawType(typeName: "Int") == .int)
    }

    /// A user module named before a stdlib name must not bind to this table.
    @Test func rawTypeRejectsAnyOtherModule() {
        #expect(RawType(typeName: "MyModule.String") == nil)
        #expect(RawType(typeName: "Foundation.String") == nil)
        #expect(RawType(typeName: "Schemas.Int") == nil)
    }

    /// `Swift.Foo.Bar` is a nested type inside the module, not a qualified leaf.
    @Test func rawTypeRejectsADeeperPath() {
        #expect(RawType(typeName: "Swift.Foo.String") == nil)
        #expect(RawType(typeName: "Swift.Outer.Inner") == nil)
    }

    @Test func rawTypeRejectsAQualifiedNonRawType() {
        #expect(RawType(typeName: "Swift.Duration") == nil)
        #expect(RawType(typeName: "Swift.Never") == nil)
    }

    // MARK: - Composite parsing

    @Test func qualifiedLeafComposesThroughTheParser() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Swift.String")
                == DerivationStrategist.memberGenerator(forTypeName: "String")
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Foundation.Date")
                == DerivationStrategist.memberGenerator(forTypeName: "Date")
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Foundation.UUID")
                == DerivationStrategist.memberGenerator(forTypeName: "UUID")
        )
    }

    /// The spellings that actually appear: generated code writes them inside containers.
    @Test func qualifiedLeavesComposeInsideContainers() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Swift.String?")
                == DerivationStrategist.memberGenerator(forTypeName: "String?")
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[Swift.Int]")
                == DerivationStrategist.memberGenerator(forTypeName: "[Int]")
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "[String: Swift.String]")
                == DerivationStrategist.memberGenerator(forTypeName: "[String: String]")
        )
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Set<Swift.String>")
                == DerivationStrategist.memberGenerator(forTypeName: "Set<String>")
        )
    }

    /// A qualified typealias resolves by the same route `TimeInterval` already took.
    @Test func qualifiedTypeAliasResolves() {
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Foundation.TimeInterval")
                == DerivationStrategist.memberGenerator(forTypeName: "Double")
        )
    }

    /// `Unicode` is not a strippable module, so the `knownValueGenerator` entry keyed on the
    /// dotted spelling still matches as written. A blanket single-dot strip would have broken it.
    @Test func unicodeScalarSurvivesUntouched() {
        #expect(DerivationStrategist.memberGenerator(forTypeName: "Unicode.Scalar") != nil)
        #expect(
            DerivationStrategist.memberGenerator(forTypeName: "Unicode.Scalar")
                == DerivationStrategist.memberGenerator(forTypeName: "UnicodeScalar")
        )
    }

    /// The resolver must never see a stripped name. If it did, a source that said `Swift.Foo`
    /// could bind to a user type called `Foo` — a different type with a working generator, which
    /// is the worst possible outcome: silently wrong rather than declined.
    @Test func aStrippedNameIsNeverOfferedToTheResolver() {
        var asked: [String] = []
        let resolve: DerivationStrategist.CustomTypeResolver = { name in
            asked.append(name)
            return DerivationStrategist.ComposedGenerator(expression: "Gen<Foo>.foo()")
        }
        _ = DerivationStrategist.composedGenerator(forTypeName: "Swift.Foo", resolve: resolve)
        #expect(asked == ["Swift.Foo"])
        #expect(!asked.contains("Foo"))
    }

    /// A qualified custom type reaches the resolver under its own key, untouched.
    @Test func qualifiedCustomTypesReachTheResolverUnchanged() {
        var asked: [String] = []
        let resolve: DerivationStrategist.CustomTypeResolver = { name in
            asked.append(name)
            return nil
        }
        _ = DerivationStrategist.composedGenerator(
            forTypeName: "Components.Schemas.Response",
            resolve: resolve
        )
        #expect(asked == ["Components.Schemas.Response"])
    }

    // MARK: - End to end

    /// The shape that motivated this: a generated struct whose only initializer parameter is a
    /// dictionary of qualified primitives. Before the fix it derived nothing.
    @Test func aGeneratedStructDerivesFromQualifiedMembers() {
        let shape = TypeShape(
            name: "Metadata",
            kind: .struct,
            inheritedTypes: ["Codable", "Hashable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "additionalProperties",
                                         typeName: "[String: Swift.String]")],
            hasUserInit: true,
            initializers: [
                InitializerSignature(
                    parameters: [InitializerParameter(label: "additionalProperties",
                                                      typeName: "[String: Swift.String]")],
                    isFailable: false,
                    isThrowing: false
                )
            ],
            enumCases: []
        )

        if case .todo = DerivationStrategist.strategy(for: shape) {
            Issue.record("a struct over [String: Swift.String] must derive")
        }
    }

    /// A `RawRepresentable` enum whose raw type is written qualified.
    @Test func aQualifiedRawRepresentableEnumDerives() {
        let shape = TypeShape(
            name: "Kind",
            kind: .enum,
            inheritedTypes: ["Swift.String", "Codable"],
            hasUserGen: false,
            storedMembers: [],
            hasUserInit: false,
            initializers: [],
            enumCases: []
        )

        if case .todo = DerivationStrategist.strategy(for: shape) {
            Issue.record("an enum with a Swift.String raw type must derive")
        }
    }
}
