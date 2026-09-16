import PropertyLawCore
import Testing

/// A struct with no stored properties derives as `Gen.always(T())` — issue #48.
///
/// Most of these tests are refusals, deliberately. The admission condition is
/// the whole risk: a `T()` that does not exist is a build error taking the
/// generated test target with it, where `.todo` names the problem.
struct StatelessDerivationTests {

    private func shape(
        kind: TypeShape.Kind = .struct,
        hasUserInit: Bool = false,
        initializers: [InitializerSignature] = [],
        hasUserGen: Bool = false,
        hasPrimaryDeclaration: Bool = true
    ) -> TypeShape {
        TypeShape(
            name: "Registrar",
            kind: kind,
            inheritedTypes: ["Equatable"],
            hasUserGen: hasUserGen,
            hasUserInit: hasUserInit,
            initializers: initializers,
            hasPrimaryDeclaration: hasPrimaryDeclaration
        )
    }

    private func isTodo(_ strategy: DerivationStrategy) -> Bool {
        if case .todo = strategy { return true }
        return false
    }

    // MARK: - Admitted

    @Test("a memberless struct with no init derives Gen.always(T())")
    func memberlessStructDerives() {
        let strategy = DerivationStrategist.strategy(for: shape())
        #expect(strategy == .initializerBased(arguments: []))
        #expect(
            GeneratorExpressionEmitter.expression(typeName: "Registrar", strategy: strategy)
                == "Gen.always(Registrar())"
        )
        #expect(strategy.requiredImports.isEmpty)
    }

    @Test("an explicit callable init() is admitted")
    func explicitNoArgumentInitDerives() {
        let strategy = DerivationStrategist.strategy(for: shape(
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: [], accessLevel: .public)]
        ))
        #expect(strategy == .initializerBased(arguments: []))
    }

    @Test("a fileprivate init() is reachable from the peer macro's own file")
    func fileprivateInitDerivesInSameFile() {
        let restricted = shape(
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: [], accessLevel: .fileprivate)]
        )
        #expect(DerivationStrategist.strategy(for: restricted, emissionSite: .sameFile)
            == .initializerBased(arguments: []))
        #expect(isTodo(DerivationStrategist.strategy(for: restricted, emissionSite: .separateFile)))
    }

    @Test("a user gen() still wins")
    func userGenWins() {
        #expect(DerivationStrategist.strategy(for: shape(hasUserGen: true)) == .userGen)
    }

    // MARK: - Refused

    /// Swift suppresses the implicit `init()` once the body declares any `init`.
    @Test("an init that takes arguments suppresses T()")
    func argumentInitRefuses() {
        let strategy = DerivationStrategist.strategy(for: shape(
            hasUserInit: true,
            initializers: [InitializerSignature(parameters: [
                InitializerParameter(label: "registry", typeName: "SomeRegistry")
            ])]
        ))
        #expect(isTodo(strategy))
    }

    /// `hasUserInit` with nothing captured — an `async` or variadic `init` the
    /// inspector skips. Unknown is not permission.
    @Test("an init the scanner could not capture refuses")
    func uncapturedInitRefuses() {
        #expect(isTodo(DerivationStrategist.strategy(for: shape(hasUserInit: true))))
    }

    @Test("a failable, throwing or private init() refuses")
    func unusableNoArgumentInitRefuses() {
        let unusable = [
            InitializerSignature(parameters: [], isFailable: true),
            InitializerSignature(parameters: [], isThrowing: true),
            InitializerSignature(parameters: [], accessLevel: .private)
        ]
        for initializer in unusable {
            let strategy = DerivationStrategist.strategy(for: shape(
                hasUserInit: true, initializers: [initializer]
            ))
            #expect(isTodo(strategy), "admitted \(initializer)")
        }
    }

    /// A class inherits its superclass's designated initializers, and the
    /// inheritance clause cannot say whether `Registrar: Base` names a class.
    @Test("classes, actors and enums are not admitted")
    func nonStructsRefuse() {
        for kind in [TypeShape.Kind.class, .actor, .enum] {
            #expect(isTodo(DerivationStrategist.strategy(for: shape(kind: kind))), "admitted \(kind)")
        }
    }

    /// An extension-only shape is empty for want of information, and its kind
    /// is a default — it may be an enum.
    @Test("a type only extended in the target is not admitted")
    func extensionOnlyRefuses() {
        let strategy = DerivationStrategist.strategy(for: shape(hasPrimaryDeclaration: false))
        #expect(isTodo(strategy))
    }

    // MARK: - Composition

    /// Most stateless types reach a generator as a member of something else —
    /// through the resolver, which inlines the expression.
    @Test("a stateless member composes into its owner")
    func statelessMemberComposes() {
        let owner = TypeShape(
            name: "Pipeline",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [
                StoredMember(name: "registrar", typeName: "Registrar"),
                StoredMember(name: "count", typeName: "Int")
            ]
        )
        let resolver = GeneratorResolver(types: [owner, shape()])
        let strategy = DerivationStrategist.strategy(for: owner, resolve: resolver.customTypeGenerator)
        guard case .memberwiseArbitrary(let members) = strategy else {
            Issue.record("expected memberwise, got \(strategy)")
            return
        }
        #expect(members.first?.generatorExpression == "Gen.always(Registrar())")
    }
}
