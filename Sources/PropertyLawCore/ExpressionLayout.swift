/// The one layout rule for a generator expression that spans lines.
///
/// Every emitter renders its expression as if the first line started at
/// column 0, and indents each continuation line relative to that line: a
/// chained `.map` or `.compactMap` sits at 0, under the line it continues, a
/// `Gen.oneOf(` list's cases sit at 4, and its closing `)` at 0. So the last
/// line of every expression sits at column 0, and an expression placed after
/// another one's last line starts on a line at column 0 as well.
///
/// Whoever places an expression on a line indented further moves its
/// continuation lines by that line's indentation, and nothing else does:
/// `EnumCaseEmitter` by 4 for each case, the generated test stub by 12 for
/// `using:`, the recursive helper by the column of each `return`, the scaffold
/// stub by the column of its body. Each site adds only its own column, so an
/// expression nested at any depth comes out at the right place.
///
/// Public because a consumer that splices `GeneratorExpressionEmitter`'s or
/// `MemberwiseEmitter`'s output into its own template is one of those sites.
/// Before this rule, `MemberwiseEmitter` put its `.map` at an absolute column
/// 12, which suited only a splice after `using:` at column 12; now the caller
/// adds its own column.
public enum ExpressionLayout {

    /// `expression` with every continuation line moved `column` spaces right,
    /// as it reads when its first line is placed on a line indented `column`.
    /// The first line is left alone, since it continues whatever precedes it
    /// on its line. Empty lines stay empty rather than gaining trailing
    /// whitespace.
    public static func indentingContinuationLines(of expression: String, by column: Int) -> String {
        let indent = String(repeating: " ", count: column)
        return expression
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in index == 0 || line.isEmpty ? String(line) : indent + line }
            .joined(separator: "\n")
    }
}
