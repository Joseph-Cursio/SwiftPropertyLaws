/// Every flag `PropertyLawDiscoveryTool` accepts, spelled as it appears in argv.
///
/// `ToolInvocation` switches over this exhaustively, so a flag cannot be
/// parsed without a case here, and `CaseIterable` lets a test enumerate them.
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
