import Testing
import PropertyBased
import Foundation

/// Validation that the generator expressions `DerivationStrategist`
/// (PropertyLawCore, Tier 1) emits for composite members actually compile
/// and run against the live `swift-property-based` engine. PropertyLawCore
/// only produces *strings* and doesn't link `PropertyBased`, so its own
/// tests can't catch a wrong combinator name or signature — this test, in a
/// target that links the engine, is the backstop.
///
/// Each binding mirrors `memberGenerator(forTypeName:)` output verbatim; the
/// explicit result-type annotation asserts the composed combinators produce
/// exactly the type the parser claims (e.g. `.optional` → `Int?`,
/// `.set(ofAtMost:)` → `Set<Int>`, `zip(...).dictionary(ofAtMost:)` →
/// `[String: Int]`). If this compiles and runs, the emitted generators are
/// valid downstream.
struct CompositeGeneratorCompileTests {
    private struct Bag: Equatable { let items: [Int] }
    private struct Order: Equatable { let id: Int; let skus: [String] }
    /// A custom init (unlabeled + labeled) — mirrors the Tier 6
    /// initializer-based emission shape.
    private struct Tagged: Equatable {
        let id: Int
        let label: String
        init(_ id: Int, label: String) {
            self.id = id
            self.label = label
        }
    }
    /// Plain + payload cases — mirrors the Tier 4 enum emission shape.
    private enum Shape: Equatable {
        case empty
        case circle(radius: Int)
        case rect(width: Int, height: Int)
    }

    /// 11 stored properties — over the flat zip-10 limit, so the emitter nests.
    private struct Wide11: Equatable {
        let m0, m1, m2, m3, m4, m5, m6, m7, m8, m9, m10: Int
    }

    /// The nested `zip` shape `MemberwiseEmitter.nestedZip` emits for an
    /// 11-member type: an outer `zip` of a 10-group `zip` and the lone 11th
    /// generator, read as `$0.0.N` / `$0.1`. If this compiles and runs, the
    /// emitted nested generators are valid downstream (PropertyLawCore only
    /// produces strings and can't catch a wrong tuple-access shape itself).
    @Test func nestedMemberwiseGeneratorCompilesAndRuns() {
        var rng = Xoshiro(seed: (5, 6, 7, 8))
        let wide: Wide11 = zip(
            zip(
                Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(),
                Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int(), Gen<Int>.int()
            ),
            Gen<Int>.int()
        )
        .map {
            Wide11(
                m0: $0.0.0, m1: $0.0.1, m2: $0.0.2, m3: $0.0.3, m4: $0.0.4,
                m5: $0.0.5, m6: $0.0.6, m7: $0.0.7, m8: $0.0.8, m9: $0.0.9, m10: $0.1
            )
        }
        .run(using: &rng)
        // The point is that it compiled and ran; equality with itself is a
        // no-op use that keeps the binding from being optimized to a warning.
        #expect(wide == wide)
    }

    @Test func compositeGeneratorsCompileAndRunAgainstEngine() {
        var rng = Xoshiro(seed: (1, 2, 3, 4))

        // "Int?"
        let optional: Int? = Gen<Int>.int().optional.run(using: &rng)
        // "[Int]"
        let array: [Int] = Gen<Int>.int().array(of: 0...8).run(using: &rng)
        // "[String]"
        let stringArray: [String] = Gen<Character>.letterOrNumber
            .string(of: 0...8).array(of: 0...8).run(using: &rng)
        // "Set<Int>"
        let set: Set<Int> = Gen<Int>.int().set(ofAtMost: 0...8).run(using: &rng)
        // "[String: Int]"
        let dictionary: [String: Int] = zip(
            Gen<Character>.letterOrNumber.string(of: 0...8),
            Gen<Int>.int()
        ).dictionary(ofAtMost: 0...8).run(using: &rng)
        // "[Int?]"
        let arrayOfOptional: [Int?] = Gen<Int>.int()
            .optional.array(of: 0...8).run(using: &rng)

        // Known value types (Tier 2): "Character", "Date", "[Date]".
        let character: Character = Gen<Character>.letterOrNumber.run(using: &rng)
        let date: Date = Gen<Date>.date.run(using: &rng)
        let dates: [Date] = Gen<Date>.date.array(of: 0...8).run(using: &rng)

        // Memberwise composition lifted through the synthesized init.
        let bag: Bag = Gen<Int>.int()
            .array(of: 0...8).map { Bag(items: $0) }.run(using: &rng)
        let order: Order = zip(
            Gen<Int>.int(),
            Gen<Character>.letterOrNumber.string(of: 0...8).array(of: 0...8)
        ).map { Order(id: $0.0, skus: $0.1) }.run(using: &rng)

        // Tier 6 — lift through a user init (unlabeled first arg, labeled second).
        let tagged: Tagged = zip(
            Gen<Int>.int(),
            Gen<Character>.letterOrNumber.string(of: 0...8)
        ).map { Tagged($0.0, label: $0.1) }.run(using: &rng)

        // Tier 4 — oneOf over plain + payload enum cases.
        let shape: Shape = Gen.oneOf(
            Gen.always(Shape.empty).eraseToAny(),
            Gen<Int>.int().map { Shape.circle(radius: $0) }.eraseToAny(),
            zip(Gen<Int>.int(), Gen<Int>.int()).map { Shape.rect(width: $0.0, height: $0.1) }.eraseToAny()
        ).run(using: &rng)

        // Reaching here means every expression type-checked and produced a
        // value of the asserted type. Touch each so nothing is dead.
        _ = optional
        #expect(array.count <= 8)
        #expect(stringArray.count <= 8)
        #expect(set.count <= 8)
        #expect(dictionary.count <= 8)
        #expect(arrayOfOptional.count <= 8)
        #expect(bag.items.count <= 8)
        _ = order
        _ = character
        _ = date
        #expect(dates.count <= 8)
        _ = tagged
        _ = shape
    }
}
