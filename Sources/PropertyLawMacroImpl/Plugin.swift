import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// Compiler-plugin entry point. Registers every macro implementation
/// the user-facing `PropertyLawMacro` module forwards to.
@main
struct PropertyLawMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        PropertyLawSuiteMacro.self,
        DiscoverableMacro.self,
        InteractionInvariantTestsMacro.self,
        ValueSemanticTestsMacro.self,
        DefensiveCopyTestsMacro.self,
        StableIdentityTestsMacro.self
    ]
}
