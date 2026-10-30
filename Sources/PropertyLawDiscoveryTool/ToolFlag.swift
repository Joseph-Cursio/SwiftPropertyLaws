/// Every flag `PropertyLawDiscoveryTool` accepts, spelled as it appears in argv.
///
/// `ToolInvocation` switches over this exhaustively, so a flag cannot be
/// parsed without a case here, and `CaseIterable` lets a test enumerate them.
///
/// The discovery plugin cannot import this type, because a `CommandPlugin`
/// runs the tool as a process and links nothing. Its own parser once fell two
/// flags behind with nothing to say so. `PropertyLawDiscoveryPluginTests` now
/// checks that the plugin accepts and forwards every case except the two it
/// supplies itself.
enum ToolFlag: String, CaseIterable, Sendable {
    case target = "--target"
    case output = "--output"
    case scaffoldOut = "--scaffold-out"
    case sourceFiles = "--source-files"
    case contextFiles = "--context-files"
    case extraImport = "--extra-import"
    case advisory = "--advisory"
    case advisoryMin = "--advisory-min"
}
