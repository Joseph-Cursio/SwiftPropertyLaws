import Testing
@testable import PropertyLawCore

/// **Every enum that failed to derive was reported the same way**, with a
/// sentence written before Tier 4 case enumeration existed:
///
/// > not `CaseIterable` and no recognized stdlib raw type … or add
/// > `: CaseIterable`.
///
/// Two things wrong with that. It conflates four unrelated causes. And for the
/// commonest one the advice **cannot be followed**: Swift forbids `CaseIterable`
/// on an enum with associated values, and in the road-test corpus 264 of the
/// case declarations across 113 enums carry them.
///
/// Measured on that corpus after the split: of the 68 enums in the bucket,
/// **68 were "payload type unresolved" and none were about `CaseIterable`** —
/// the label was wrong for every single one.
struct EnumTodoReasonTests {

    private func enumShape(
        _ cases: [EnumCase],
        inherits: [String] = ["Equatable"]
    ) -> TypeShape {
        TypeShape(
            name: "Subject",
            kind: .enum,
            inheritedTypes: inherits,
            hasUserGen: false,
            enumCases: cases
        )
    }

    private func reason(for shape: TypeShape) -> String {
        guard case .todo(let reason) = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected .todo")
            return ""
        }
        return reason
    }

    /// A namespace enum is *uninhabited* — no value exists, so no generator can.
    /// `: CaseIterable` would not help either: `allCases` would be empty and the
    /// generator would never yield.
    @Test("a caseless enum is reported as uninhabited, not as missing CaseIterable")
    func caselessEnum() {
        let text = reason(for: enumShape([]))
        #expect(text.contains("declares no cases"))
        #expect(text.contains("uninhabited"))
        #expect(text.contains("add `: CaseIterable`") == false)
    }

    @Test("an over-arity case names the case and its count")
    func overArityCase() {
        let wide = EnumCase(
            name: "big",
            associatedValues: (0 ..< 11).map {
                InitializerParameter(label: "v\($0)", typeName: "Int")
            }
        )
        let text = reason(for: enumShape([wide]))
        #expect(text.contains("case `big` has 11 associated values"))
        #expect(text.contains("supports up to \(DerivationStrategist.memberwiseArityLimit)"))
    }

    /// The one that was 100% of the corpus bucket.
    @Test("an unresolvable payload names the case and the offending type")
    func unresolvablePayload() {
        let text = reason(for: enumShape([
            EnumCase(name: "ok", associatedValues: [
                InitializerParameter(label: nil, typeName: "Int")
            ]),
            EnumCase(name: "opaque", associatedValues: [
                InitializerParameter(label: nil, typeName: "UnsafeContinuation<Void, Error>")
            ])
        ]))
        #expect(text.contains("case `opaque`"))
        #expect(text.contains("`UnsafeContinuation<Void, Error>`"))
        #expect(text.contains("resolves to no generator"))
    }

    /// The impossible advice must be gone from every associated-value arm —
    /// this is the assertion the old message would have failed.
    @Test("an associated-value enum is never told to add CaseIterable")
    func neverSuggestsCaseIterableForPayloadEnums() {
        let text = reason(for: enumShape([
            EnumCase(name: "opaque", associatedValues: [
                InitializerParameter(label: nil, typeName: "SomeOpaqueThing")
            ])
        ]))
        #expect(text.contains("CaseIterable") == false)
    }

    /// **The diagnostic must use the same resolver the strategy did, or it
    /// names the wrong culprit.** With two failing-looking cases where only the
    /// second is genuinely unresolvable, a resolver-blind diagnostic reports the
    /// first — sending the user to inspect a type that resolves fine.
    ///
    /// Caught by mutation: dropping `resolve:` from the diagnostic left every
    /// other test in this file green.
    @Test("the diagnostic blames the case the resolver actually could not supply")
    func diagnosticBlamesTheRightCase() {
        let shape = enumShape([
            EnumCase(name: "resolvable", associatedValues: [
                InitializerParameter(label: nil, typeName: "Custom")
            ]),
            EnumCase(name: "opaque", associatedValues: [
                InitializerParameter(label: nil, typeName: "Opaque")
            ])
        ])
        let resolve: DerivationStrategist.CustomTypeResolver = { name in
            name == "Custom"
                ? DerivationStrategist.ComposedGenerator(expression: "Gen<Int>.int()")
                : nil
        }
        guard case .todo(let reason) = DerivationStrategist.strategy(
            for: shape, resolve: resolve
        ) else {
            Issue.record("expected .todo — `Opaque` resolves to nothing")
            return
        }
        #expect(reason.contains("case `opaque`"))
        #expect(reason.contains("`Opaque`"))
        // The resolvable case must not be blamed.
        #expect(reason.contains("case `resolvable`") == false)
        #expect(reason.contains("`Custom`") == false)
    }

    /// The diagnostic consults the same resolver the strategy did, so it can't
    /// call a type unresolvable that the plugin would in fact have resolved.
    @Test("a payload the resolver can supply is not reported as unresolvable")
    func resolverIsConsulted() {
        let shape = enumShape([
            EnumCase(name: "wrapped", associatedValues: [
                InitializerParameter(label: nil, typeName: "Custom")
            ])
        ])
        let resolve: DerivationStrategist.CustomTypeResolver = { name in
            name == "Custom"
                ? DerivationStrategist.ComposedGenerator(expression: "Gen<Int>.int()")
                : nil
        }
        guard case .enumCases = DerivationStrategist.strategy(for: shape, resolve: resolve) else {
            Issue.record("expected the resolver to supply the payload generator")
            return
        }
    }

    /// The residual arm keeps the `CaseIterable` wording, and that is correct
    /// *there*: it describes an enum whose cases were never captured, which the
    /// conformance genuinely could rescue.
    ///
    /// **It is unreachable through `strategy(for:)`** — an enum with cases that
    /// all resolve derives instead of falling to `.todo` — so it is exercised by
    /// calling the diagnostic directly. Retained because `todoReason` is a total
    /// function over `TypeShape` and some caller may build a shape the
    /// strategist never would.
    @Test("the residual arm keeps the CaseIterable advice")
    func residualArm() {
        let text = DerivationStrategist.todoReason(for: TypeShape(
            name: "Subject", kind: .enum, inheritedTypes: [], hasUserGen: false,
            enumCases: [EnumCase(name: "a", associatedValues: [])]
        ))
        #expect(text.contains("cases could not be enumerated"))
        #expect(text.contains("neither `CaseIterable` nor"))
    }

    /// Nothing above should have changed the happy path.
    @Test("a payload-free enum still derives by case enumeration")
    func payloadFreeStillDerives() {
        let shape = enumShape([
            EnumCase(name: "a", associatedValues: []),
            EnumCase(name: "b", associatedValues: [])
        ])
        guard case .enumCases = DerivationStrategist.strategy(for: shape) else {
            Issue.record("expected case enumeration")
            return
        }
    }

    @Test("a CaseIterable enum still short-circuits to the allCases strategy")
    func caseIterableStillWins() {
        let shape = enumShape(
            [EnumCase(name: "a", associatedValues: [])],
            inherits: ["CaseIterable"]
        )
        #expect(DerivationStrategist.strategy(for: shape) == .caseIterable)
    }
}
