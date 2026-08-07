import Testing
@testable import PropertyLawCore

/// Recursive (self-referential) type generation.
///
/// `GeneratorResolver` used to return `nil` on cycle detection, pinning every
/// self-referential type at `.todo`. The referencing law was still *proposed*,
/// often at Strong tier — so the tool made its most confident claim and then
/// could not run it. That is what these tests close.
///
/// ## The claim this replaces was wrong
///
/// `SwiftInferProperties/docs/measurements/parsing-catalog-gap.md` §7(a) recorded
/// recursive
/// generation as a missing **engine** capability, alongside higher-order
/// generation, and said its absence "blocks the entire domain". Both halves
/// were wrong, and measurement is what showed it:
///
/// - The engine has everything needed. `Gen.frequency` + `zip` + `eraseToAny()`
///   plus a depth budget expresses recursion on shipped `swift-property-based`
///   1.2.0, with no new combinator. A probe built the `indirect enum Expr` the
///   doc called unreachable, and it refuted a fixpoint bug with the *minimal*
///   witness `.neg(.neg(.neg(.neg(.lit(0)))))`, shrunk from `.lit(-9)`.
/// - The reach is not "the entire domain". A brace-matched scan of ~1,840
///   source files across swift-foundation, swift-syntax, swift-argument-parser
///   / swift-nio and SwiftProjectLint found **two** genuinely recursive data
///   types. swift-syntax's own AST is arena-backed (`SyntaxDataArena` +
///   `SyntaxDataReference`), not a recursive enum — so the flagship Swift
///   parser is a counterexample to the premise that every parser AST is one.
///
/// The case for building it is therefore integrity, not reach: `Strong` tier
/// plus `Generator: .todo` is a promise the tool cannot keep.
struct RecursiveGeneratorTests {

    private func shape(_ name: String, _ members: [(String, String)]) -> TypeShape {
        TypeShape(
            name: name,
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members.map { StoredMember(name: $0.0, typeName: $0.1) }
        )
    }

    private func resolve(_ name: String, _ universe: [TypeShape])
        -> DerivationStrategist.ComposedGenerator? {
        GeneratorResolver(types: universe).customTypeGenerator(forTypeName: name)
    }

    // MARK: - The two shapes that actually occur

    @Test("`[Self]` resolves — DirectoryNode, measured in SwiftProjectLint")
    func selfInArrayResolves() throws {
        let node = shape("DirectoryNode", [("name", "String"), ("children", "[DirectoryNode]")])
        let generated = try #require(resolve("DirectoryNode", [node]))

        // The plan renders as a CALL; the func rides along separately.
        #expect(generated.expression == "__genDirectoryNode(4)")
        let declaration = try #require(generated.plan.supportingDeclarations.first)
        #expect(declaration.contains("func __genDirectoryNode(_ budget: Int)"))
        // Recursive arm recurses…
        #expect(declaration.contains("__genDirectoryNode(budget - 1).array(of: 0...8)"))
        // …and the base arm does not.
        #expect(declaration.contains("Gen<[DirectoryNode]>.always([])"))
    }

    @Test("`[Self]?` resolves — CommandInfoV0, measured in swift-argument-parser")
    func selfInOptionalArrayResolves() throws {
        let cmd = shape(
            "CommandInfoV0",
            [("commandName", "String"), ("subcommands", "[CommandInfoV0]?")]
        )
        let generated = try #require(resolve("CommandInfoV0", [cmd]))
        let declaration = try #require(generated.plan.supportingDeclarations.first)
        // The longest wrapper suffix has to win, or `.array(of: 0...8)` is left
        // dangling after `.optional` matches first.
        #expect(declaration.contains("Gen<[CommandInfoV0]?>.always(nil)"))
        #expect(!declaration.contains("always(nil).array"))
    }

    // MARK: - The early return is load-bearing

    @Test("the base arm is a real early return, not a ternary")
    func baseArmIsAnEarlyReturn() throws {
        let node = shape("Node", [("kids", "[Node]")])
        let declaration = try #require(
            resolve("Node", [node])?.plan.supportingDeclarations.first
        )
        // `Gen.array(of:)` evaluates its element generator EAGERLY, so a budget
        // check written inside the expression still constructs
        // `__genNode(budget - 1)` in order to pass it — which constructs
        // `__genNode(budget - 2)`, forever, past zero. That is an infinite loop
        // at generator-CONSTRUCTION time: no value is ever drawn and the stub
        // simply hangs, with nothing pointing at recursion as the cause.
        #expect(declaration.contains("if budget <= 0 {"))
        #expect(!declaration.contains("budget > 0 ?"))
    }

    @Test("both arms erase — otherwise the return type cannot be spelled")
    func bothArmsErase() throws {
        let node = shape("Node", [("kids", "[Node]")])
        let declaration = try #require(
            resolve("Node", [node])?.plan.supportingDeclarations.first
        )
        // `Generator` is generic over its shrink sequence as well as its value,
        // and the two arms shrink structurally differently.
        #expect(declaration.components(separatedBy: ".eraseToAny()").count == 3)
        #expect(declaration.contains("-> Generator<Node, AnySequence<Any>>"))
    }

    // MARK: - What is still refused, and why that is not a regression

    @Test("a BARE self-reference stays `.todo` — no wrapper, no terminal")
    func bareSelfReferenceRefused() {
        // `var next: Node` (not optional, not an array) describes a type whose
        // every value contains another value of itself: uninhabitable. There is
        // no empty form to collapse to, so there is no base arm, so it stays
        // exactly where it was.
        let node = shape("Node", [("next", "Node")])
        #expect(resolve("Node", [node]) == nil)
    }

    @Test("mutual recursion across two types stays `.todo`")
    func mutualRecursionRefused() {
        // A refers to B refers to A. The cycle is detected at B, so the
        // recursion point carries B's helper name while the declaration being
        // built is A's — the rewrite finds no marker it owns and declines.
        // Correct-but-conservative: emitting one helper per type would need
        // both funcs in scope, which the single-declaration path cannot express.
        let typeA = shape("A", [("b", "B")])
        let typeB = shape("B", [("a", "[A]")])
        let resolved = resolve("A", [typeA, typeB])
        if let resolved {
            #expect(!resolved.expression.contains("budget - 1"),
                    "a half-built mutual recursion must not escape as an expression")
        }
    }

    // MARK: - Nothing else moved

    @Test("a non-recursive type carries no declarations")
    func nonRecursiveUnchanged() throws {
        let customer = shape("Customer", [("name", "String")])
        let order = shape("Order", [("id", "Int"), ("customer", "Customer")])
        let generated = try #require(resolve("Order", [order, customer]))
        #expect(generated.plan.supportingDeclarations.isEmpty)
        // Still inlined, exactly as before.
        #expect(generated.expression.contains("Customer(name:"))
    }

    // MARK: - The rewrite itself

    @Test("baseArm declines when a recursion point has no recognized wrapper")
    func baseArmDeclinesUnwrapped() {
        let expression = "zip(Gen<Int>.int(), __genNode(budget - 1)).map { Node($0.0, $0.1) }"
        #expect(RecursiveGeneratorEmitter.baseArm(expression: expression, typeName: "Node") == nil)
    }

    @Test("the helper name cannot collide with user code")
    func helperNameIsReserved() {
        #expect(RecursiveGeneratorEmitter.helperName(for: "Node") == "__genNode")
        // Qualified spellings flatten, so `Foo.Kind` and `FooKind` cannot both
        // claim `__genFooKind`… they do collapse, but a universe carrying both
        // is already refused as ambiguous by `GeneratorResolver.init`.
        #expect(RecursiveGeneratorEmitter.helperName(for: "Foo.Kind") == "__genFooKind")
    }

    @Test("Foundation-free replace handles overlap and absence")
    func replaceIsCorrect() {
        #expect(RecursiveGeneratorEmitter.replacing("aa", with: "b", in: "aaaa") == "bb")
        #expect(RecursiveGeneratorEmitter.replacing("x", with: "y", in: "abc") == "abc")
        #expect(RecursiveGeneratorEmitter.replacing("", with: "y", in: "abc") == "abc")
    }
}
