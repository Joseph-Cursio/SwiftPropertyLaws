import SwiftParser
import SwiftSyntax
import Testing
@testable import PropertyLawSyntaxSupport

/// Three swift-collections carriers took down the whole generated suite on the same shape —
/// `_DequeSlot`, `_HeapNode` and `_HashTable.Bucket`, each `assert(offset >= 0)` in an
/// initializer a derived generator was calling with arbitrary `Int`s.
struct InitializerPreconditionDetectorTests {

    func statesPrecondition(_ source: String) -> Bool {
        let file = Parser.parse(source: source)
        var found: InitializerDeclSyntax?
        for statement in file.statements {
            guard let decl = statement.item.as(StructDeclSyntax.self) else { continue }
            for member in decl.memberBlock.members {
                if let initDecl = member.decl.as(InitializerDeclSyntax.self) { found = initDecl }
            }
        }
        guard let initDecl = found else { return false }
        return InitializerPreconditionDetector.statesPrecondition(initDecl)
    }

    /// The `_HashTable.Bucket` shape, verbatim in structure.
    @Test("an assert on a parameter is a precondition")
    func assertDetected() {
        #expect(statesPrecondition("""
            struct Bucket { init(offset: Int) { assert(offset >= 0); self.offset = offset } }
            """))
    }

    @Test("precondition counts too")
    func preconditionDetected() {
        #expect(statesPrecondition("""
            struct Slot { init(at position: Int) { precondition(position >= 0) } }
            """))
    }

    /// `_HeapNode` guards its second assertion with `#if COLLECTIONS_INTERNAL_CHECKS`. A
    /// debug-only assertion is still a statement that the argument is invalid, and the
    /// generated suite is itself built in debug — so the walk must see through `#if`.
    @Test("an assertion behind #if still counts")
    func conditionalCompilationAssertDetected() {
        #expect(statesPrecondition("""
            struct Node {
                init(offset: Int) {
                    #if COLLECTIONS_INTERNAL_CHECKS
                    assert(offset >= 0)
                    #endif
                }
            }
            """))
    }

    @Test("an ordinary initializer states nothing")
    func plainInitializerIsClean() {
        #expect(!statesPrecondition("""
            struct Point { init(x: Int) { self.x = x } }
            """))
    }

    /// `fatalError` marks an unreachable path or an unimplemented stub — not a constraint on
    /// arguments. Treating it as one would decline initializers that accept anything.
    @Test("fatalError is not a precondition")
    func fatalErrorIsNotAPrecondition() {
        #expect(!statesPrecondition("""
            struct Stub { init(x: Int) { fatalError("unimplemented") } }
            """))
    }

    /// An assert on something OTHER than a parameter is still a precondition on the call: the
    /// generator cannot know which values reach it, so the distinction is not usable.
    @Test("an assert not mentioning a parameter still counts")
    func assertOnDerivedValueCounts() {
        #expect(statesPrecondition("""
            struct Wrapper { init(x: Int) { let y = x * 2; assert(y != 0); self.y = y } }
            """))
    }
}

/// `_HeapNode` is why delegation is tracked: its `init(offset:)` asserts nothing and forwards
/// to `init(offset:level:)`, which asserts `offset >= 0`. A body-only check calls the first
/// one clean, derivation picks it, and the generated suite aborts anyway.
extension InitializerPreconditionDetectorTests {

    private func delegates(_ source: String) -> Bool {
        let file = Parser.parse(source: source)
        var found: InitializerDeclSyntax?
        for statement in file.statements {
            guard let decl = statement.item.as(StructDeclSyntax.self) else { continue }
            for member in decl.memberBlock.members {
                if let initDecl = member.decl.as(InitializerDeclSyntax.self) { found = initDecl }
            }
        }
        guard let initDecl = found else { return false }
        return InitializerPreconditionDetector.delegatesToSelf(initDecl)
    }

    @Test("a self.init call is delegation")
    func selfInitIsDelegation() {
        #expect(delegates("""
            struct Node { init(offset: Int) { self.init(offset: offset, level: 0) } }
            """))
    }

    @Test("an ordinary body is not delegation")
    func plainBodyIsNotDelegation() {
        #expect(!delegates("""
            struct Node { init(offset: Int) { self.offset = offset } }
            """))
    }
}
