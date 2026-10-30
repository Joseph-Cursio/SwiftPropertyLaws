import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacros
import SwiftSyntaxMacrosGenericTestSupport
import Testing

/// `assertMacroExpansion` that fails the Swift Testing test calling it.
///
/// In swift-syntax 602, which this package resolves, the version in
/// `SwiftSyntaxMacrosTestSupport` reports a mismatch through `XCTFail`. Swift
/// Testing does not count that as a failure: Swift 6.4 records it as a warning
/// ("An API was misused") and the test passes. So no golden expansion in this
/// target could fail, and 47 of the 57 had drifted from what the macros emit
/// without anyone seeing it. swift-syntax 603 records a Swift Testing issue
/// itself; this one hands the framework-neutral assertion a handler that does
/// the same, on either version.
///
/// It takes the same arguments as the XCTest version, so the call sites did
/// not change. A declaration in this module shadows the imported one.
func assertMacroExpansion(
    _ originalSource: String,
    expandedSource expectedExpandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    macros: [String: Macro.Type],
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    SwiftSyntaxMacrosGenericTestSupport.assertMacroExpansion(
        originalSource,
        expandedSource: expectedExpandedSource,
        diagnostics: diagnostics,
        macroSpecs: macros.mapValues { MacroSpec(type: $0) },
        failureHandler: { failure in
            Issue.record(
                Comment(rawValue: failure.message),
                sourceLocation: SourceLocation(
                    fileID: failure.location.fileID,
                    filePath: failure.location.filePath,
                    line: failure.location.line,
                    column: failure.location.column
                )
            )
        },
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}
