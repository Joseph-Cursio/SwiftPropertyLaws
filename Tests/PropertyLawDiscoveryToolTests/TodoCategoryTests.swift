import PropertyLawCore
import Testing
@testable import PropertyLawDiscoveryTool

/// `todoCategory` buckets a `.todo` by substring-matching `TodoReason`'s prose,
/// which makes the summary scoreboard silently wrong in two ways: a reworded
/// reason drops to `"other"`, and a new reason containing an earlier arm's
/// substring is swallowed by it.
///
/// The second failure is not hypothetical — the access-restriction reason says
/// "stored property", so before its own arm was added it reported a
/// `private let secret: Int` as an *unsupported member type*, pointing the user
/// at an `Int`.
///
/// Every case here builds its reason by running the real strategist rather than
/// quoting a string, so a reworded diagnostic fails this test instead of quietly
/// recategorising in the field.
struct TodoCategoryTests {

    private func reason(for shape: TypeShape, site: EmissionSite = .separateFile) -> String {
        PropertyLawDiscoveryTool.todoCategory(
            for: DerivationStrategist.strategy(for: shape, emissionSite: site)
        )
    }

    private func structShape(
        _ members: [StoredMember],
        hasUserInit: Bool = false,
        initializers: [InitializerSignature] = []
    ) -> TypeShape {
        TypeShape(
            name: "Subject",
            kind: .struct,
            inheritedTypes: ["Equatable"],
            hasUserGen: false,
            storedMembers: members,
            hasUserInit: hasUserInit,
            initializers: initializers
        )
    }

    @Test("a private member is reported as an access restriction, not a bad type")
    func privateMemberCategory() {
        let category = reason(for: structShape([
            StoredMember(name: "a", typeName: "Int"),
            StoredMember(name: "secret", typeName: "Int", accessLevel: .private)
        ]))
        #expect(category == "access-restricted member (private/fileprivate)")
    }

    @Test("a fileprivate member lands in the same bucket for separate-file emission")
    func fileprivateMemberCategory() {
        let category = reason(for: structShape([
            StoredMember(name: "a", typeName: "Int"),
            StoredMember(name: "b", typeName: "Int", accessLevel: .fileprivate)
        ]))
        #expect(category == "access-restricted member (private/fileprivate)")
    }

    @Test("an unrecognized member type keeps its own bucket")
    func unsupportedTypeCategory() {
        let category = reason(for: structShape([
            StoredMember(name: "a", typeName: "SomeUnknownType")
        ]))
        #expect(category == "unsupported member type (nested/custom)")
    }

    @Test("a non-struct keeps its own bucket")
    func nonStructCategory() {
        let category = reason(for: TypeShape(
            name: "Subject", kind: .class, inheritedTypes: ["Equatable"], hasUserGen: false
        ))
        #expect(category == "non-struct (class/actor/enum-payload)")
    }

    @Test("an empty struct keeps its own bucket")
    func noStoredPropertiesCategory() {
        #expect(reason(for: structShape([])) == "no visible stored properties")
    }

    @Test("a user init keeps its own bucket")
    func userInitCategory() {
        let category = reason(for: structShape(
            [StoredMember(name: "a", typeName: "Int")], hasUserInit: true
        ))
        #expect(category == "user-defined init")
    }

    /// The access reason for an initializer also says "initializer", so it must
    /// be matched ahead of the user-init arm — the same ordering hazard as the
    /// member arm, one tier down.
    @Test("a private initializer is not reported as a plain user-defined init")
    func privateInitializerCategory() {
        let category = reason(for: structShape(
            [StoredMember(name: "a", typeName: "Int")],
            hasUserInit: true,
            initializers: [InitializerSignature(
                parameters: [InitializerParameter(label: "a", typeName: "Int")],
                accessLevel: .private
            )]
        ))
        #expect(category == "access-restricted initializer (private/fileprivate)")
    }

    @Test("an over-arity struct keeps its own bucket")
    func arityCategory() {
        let members = (0 ..< (DerivationStrategist.memberwiseMemberLimit + 1)).map {
            StoredMember(name: "m\($0)", typeName: "Int")
        }
        #expect(reason(for: structShape(members)) == "arity > 10")
    }

    /// The old single `"enum without CaseIterable/raw"` bucket conflated four
    /// causes and named the one remedy that is impossible for the commonest of
    /// them. On the road-test corpus all 68 members of that bucket were in fact
    /// payload-resolution failures.
    @Test("a caseless enum reports as uninhabited")
    func caselessEnumCategory() {
        let category = reason(for: TypeShape(
            name: "Subject", kind: .enum, inheritedTypes: ["Equatable"], hasUserGen: false
        ))
        #expect(category == "caseless enum (uninhabited)")
    }

    @Test("an unresolvable enum payload reports as such")
    func enumPayloadCategory() {
        let category = reason(for: TypeShape(
            name: "Subject", kind: .enum, inheritedTypes: ["Equatable"], hasUserGen: false,
            enumCases: [EnumCase(name: "c", associatedValues: [
                InitializerParameter(label: nil, typeName: "UnsafeContinuation<Void, Error>")
            ])]
        ))
        #expect(category == "enum payload type unresolved")
    }

    @Test("an over-arity enum case reports as such")
    func enumArityCategory() {
        let category = reason(for: TypeShape(
            name: "Subject", kind: .enum, inheritedTypes: ["Equatable"], hasUserGen: false,
            enumCases: [EnumCase(name: "big", associatedValues: (0 ..< 11).map {
                InitializerParameter(label: "v\($0)", typeName: "Int")
            })]
        ))
        #expect(category == "enum case over the arity limit")
    }

    /// A derived strategy has no category — the summary only lists `.todo`s.
    @Test("a non-todo strategy reports n/a")
    func derivedStrategyHasNoCategory() {
        #expect(PropertyLawDiscoveryTool.todoCategory(for: DerivationStrategy.caseIterable) == "n/a")
    }
}
