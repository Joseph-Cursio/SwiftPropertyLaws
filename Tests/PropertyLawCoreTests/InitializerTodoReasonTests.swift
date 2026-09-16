import Testing
@testable import PropertyLawCore

/// The user-`init` `.todo` reason names the parameter that stopped derivation,
/// where it used to say only that *some* initializer had *some* parameter that
/// did not resolve.
struct InitializerTodoReasonTests {

    private func parameter(_ label: String?, _ typeName: String) -> InitializerParameter {
        InitializerParameter(label: label, typeName: typeName)
    }

    private func shape(_ initializers: [InitializerSignature]) -> TypeShape {
        TypeShape(
            name: "Subject",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: [StoredMember(name: "storage", typeName: "Int")],
            hasUserInit: true,
            initializers: initializers
        )
    }

    private func reason(
        _ subject: TypeShape,
        resolve: @escaping DerivationStrategist.CustomTypeResolver = { _ in nil }
    ) -> String? {
        guard case .todo(let reason) = DerivationStrategist.strategy(for: subject, resolve: resolve) else {
            return nil
        }
        return reason
    }

    @Test("the unresolved parameter and its initializer are named")
    func namesParameter() throws {
        let text = try #require(reason(shape([
            InitializerSignature(parameters: [parameter(nil, "Widget"), parameter("count", "Int")])
        ])))
        #expect(text.contains("`init(_:count:)` takes `_: Widget`, which resolves to no generator"))
    }

    /// A declined initializer is never tried, so its parameters are not the
    /// reason — naming `Ignored` would send the reader to the wrong `init`.
    @Test("a declined initializer's parameters are not blamed")
    func skipsDeclinedInitializer() throws {
        let text = try #require(reason(shape([
            InitializerSignature(parameters: [parameter("a", "Ignored")], isFailable: true),
            InitializerSignature(parameters: [parameter("b", "Int"), parameter("c", "Blocking")])
        ])))
        #expect(text.contains("`init(b:c:)` takes `c: Blocking`"))
        #expect(!text.contains("Ignored"))
    }

    @Test("a parameter the resolver supplies is not blamed")
    func consultsResolver() throws {
        let resolved = DerivationStrategist.ComposedGenerator(expression: "Known.gen()")
        let text = try #require(reason(
            shape([InitializerSignature(parameters: [parameter("known", "Known"), parameter("other", "Other")])]),
            resolve: { $0 == "Known" ? resolved : nil }
        ))
        #expect(text.contains("takes `other: Other`"))
        #expect(!text.contains("known: Known"))
    }

    /// With nothing tried, no parameter type is at fault.
    @Test("when every initializer is declined, no parameter is blamed")
    func allDeclinedBlamesNoParameter() throws {
        let text = try #require(reason(shape([
            InitializerSignature(parameters: [parameter("a", "Widget")], isThrowing: true)
        ])))
        #expect(text.contains("don't support derivation"))
        #expect(!text.contains("resolves to no generator"))
        #expect(!text.contains("Widget"))
    }
}
