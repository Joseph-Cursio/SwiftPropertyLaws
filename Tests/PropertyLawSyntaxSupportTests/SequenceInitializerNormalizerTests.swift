import SwiftParser
import SwiftSyntax
import Testing
@testable import PropertyLawSyntaxSupport

/// `init<S: Sequence>(_ items: S) where S.Element == Element` is how essentially every Swift
/// collection is built, and Tier 6 walked past it: the parameter's declared type is the
/// generic parameter `S`, which resolves to no generator. Measured on swift-collections —
/// every public collection type reported "no initializer has all parameter types resolve to a
/// recognized generator" while declaring exactly this shape.
struct SequenceInitializerNormalizerTests {

    /// Parse one initializer out of a struct body and normalise its first parameter's type.
    private func normalized(_ source: String) -> String? {
        let file = Parser.parse(source: source)
        var found: InitializerDeclSyntax?
        for statement in file.statements {
            guard let decl = statement.item.as(StructDeclSyntax.self) else { continue }
            for member in decl.memberBlock.members {
                if let initDecl = member.decl.as(InitializerDeclSyntax.self) { found = initDecl }
            }
        }
        guard let initDecl = found,
              let parameter = initDecl.signature.parameterClause.parameters.first else {
            return nil
        }
        return SequenceInitializerNormalizer.normalizedTypeName(
            declared: parameter.type.trimmedDescription, initializer: initDecl
        )
    }

    @Test("the canonical collection constructor normalises to an array of its element")
    func canonicalShape() {
        #expect(normalized("""
            struct Bag { init<S: Sequence>(_ items: S) where S.Element == Int {} }
            """) == "[Int]")
    }

    /// swift-collections writes `__owned S`; without stripping, the name comparison fails and
    /// the whole rewrite silently does nothing on the corpus it was built for.
    @Test("an ownership sigil does not defeat the match")
    func ownershipSigilStripped() {
        #expect(normalized("""
            struct Bag { init<S: Sequence>(_ items: __owned S) where S.Element == Int {} }
            """) == "[Int]")
    }

    @Test("Collection refines Sequence and is accepted")
    func collectionConstraint() {
        #expect(normalized("""
            struct Bag { init<C: Collection>(_ items: C) where C.Element == String {} }
            """) == "[String]")
    }

    /// **The load-bearing decline.** A `Sequence`-constrained parameter with no `Element`
    /// requirement is a sequence of ANYTHING. Guessing an element type would emit a call that
    /// does not typecheck — worse than the `.todo` it replaces.
    @Test("no Element requirement means no rewrite")
    func missingElementRequirementDeclines() {
        #expect(normalized("""
            struct Bag { init<S: Sequence>(_ items: S) {} }
            """) == "S")
    }

    @Test("an unrelated constraint is left alone")
    func unrelatedConstraintUntouched() {
        #expect(normalized("""
            struct Bag { init<T: Equatable>(_ item: T) {} }
            """) == "T")
    }

    @Test("a concrete parameter type is returned unchanged")
    func concreteParameterUntouched() {
        #expect(normalized("""
            struct Bag { init(_ items: [Int]) {} }
            """) == "[Int]")
    }

    /// Two generic parameters is a shape this does not model — `init<K, V>` could be anything.
    @Test("more than one generic parameter declines")
    func multipleGenericsDecline() {
        #expect(normalized("""
            struct Bag { init<S: Sequence, T>(_ items: S, other: T) where S.Element == Int {} }
            """) == "S")
    }

    /// A generic CARRIER names its own parameter in the where clause. That is left as written
    /// and will not resolve here, so the carrier stays `.todo` — the substitution needs the
    /// enclosing declaration's generics, which a member block does not carry.
    @Test("a carrier's own generic parameter is recorded verbatim, not guessed")
    func carrierGenericRecordedVerbatim() {
        #expect(normalized("""
            struct Bag<Element> { init<S: Sequence>(_ items: S) where S.Element == Element {} }
            """) == "[Element]")
    }
}
