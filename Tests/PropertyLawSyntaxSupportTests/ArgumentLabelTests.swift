import PropertyLawCore
import SwiftParser
import SwiftSyntax
import Testing
@testable import PropertyLawSyntaxSupport

/// The labels a derived call writes. A first name of `_`, or none at all,
/// means the argument is passed unlabelled, and a generated call that wrote
/// `_:` would not compile.
struct ArgumentLabelTests {

    private func memberBlock(_ source: String) throws -> MemberBlockSyntax {
        let file = Parser.parse(source: source)
        return try #require(file.statements.first?.item.asProtocol(DeclGroupSyntax.self)).memberBlock
    }

    @Test("an initializer parameter named `_` takes no label")
    func initializerLabels() throws {
        let block = try memberBlock("""
        struct S {
            init(_ value: Int, named name: String, count: Int) {}
        }
        """)
        let labels = MemberBlockInspector.initializers(in: block).first?.parameters.map(\.label)
        #expect(labels == [nil, "named", "count"])
    }

    @Test("an enum payload named `_` or not named takes no label")
    func enumPayloadLabels() throws {
        let block = try memberBlock("""
        enum E {
            case moved(_: Int, Int, to: String)
        }
        """)
        let labels = MemberBlockInspector.enumCases(in: block).first?.associatedValues.map(\.label)
        #expect(labels == [nil, nil, "to"])
    }
}
