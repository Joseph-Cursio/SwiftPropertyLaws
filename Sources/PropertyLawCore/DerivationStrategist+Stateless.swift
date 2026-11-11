/// A struct with no stored properties — derived as `Gen.always(T())`.
///
/// **Why a constant generator is right here and wrong one tier over.**
/// `isDeclined` refuses a zero-parameter initializer, and a capacity-only one,
/// because on a type *with* state a constant draws one value from a large space
/// and reports a pass about all of them. A type with no stored properties has
/// no space: every value is the same value, so `Gen.always(T())` is not a weak
/// sample of the domain but the whole of it. `memberwiseStrategy` used to
/// decline these as "pathological for property-based testing", which conflated
/// the two cases — the laws over a stateless type are cheap to satisfy, not
/// wrong to run, and a custom `==` or `hash(into:)` on one can still be broken.
///
/// Measured before this existed (issue #48, SwiftInferProperties' corpus
/// census): **490 structs** across 19 repositories had nothing to build from
/// and sat at `.todo` — stateless registrars and strategy objects carrying
/// only computed properties and methods.
///
/// **The admission condition is the whole risk**, because `T()` that does not
/// exist is a build error that takes the generated test target with it, where
/// `.todo` at least says what is wrong. Admitted only when:
///
/// - the scanner saw the declaration (`hasPrimaryDeclaration`) — an
///   extension-only shape is empty for want of information, and its `kind` is
///   a default, so it may not even be a struct;
/// - it is a struct. A class inherits its superclass's designated initializers,
///   and a superclass is syntactically indistinguishable from a protocol in the
///   inheritance clause, so `Sub()` cannot be proven to exist;
/// - it has no stored members. `MemberBlockInspector` records observed and
///   tuple-pattern properties for exactly this reason — each would otherwise
///   read as absent while still being a required initializer argument;
/// - and either it declares no `init` in its primary body (Swift then
///   synthesizes `init()`), or it declares a zero-parameter one that is
///   callable from `emissionSite`, non-failable and non-throwing. An `init` in
///   an *extension* suppresses nothing and is not consulted.
///
/// A defaulted-parameter initializer (`init(x: Int = 0)`) would also answer
/// `T()`, and is deliberately not admitted: the shape does not record defaults.
extension DerivationStrategist {

    static func statelessStrategy(
        for shape: TypeShape,
        emissionSite: EmissionSite = .separateFile
    ) -> DerivationStrategy? {
        guard shape.hasPrimaryDeclaration,
              shape.kind == .struct,
              shape.storedMembers.isEmpty,
              hasCallableNoArgumentInit(shape, from: emissionSite) else { return nil }
        return .initializerBased(arguments: [])
    }

    /// Whether `T()` names an initializer the emitted code can call.
    static func hasCallableNoArgumentInit(
        _ shape: TypeShape,
        from emissionSite: EmissionSite
    ) -> Bool {
        guard shape.hasUserInit else { return true }
        return shape.initializers.contains { initializer in
            initializer.parameters.isEmpty
                && !initializer.isFailable
                && !initializer.isThrowing
                && initializer.accessLevel.isCallable(from: emissionSite)
        }
    }
}
