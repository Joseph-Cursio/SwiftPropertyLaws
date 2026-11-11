/// Marker peer macro that tags a function as a candidate for PRD §5.5
/// cross-function round-trip discovery and (optionally) groups it with
/// other tagged functions via the `group:` argument.
///
/// `@Discoverable` is read by the M2 discovery plugin's `--advisory`
/// pass: when two `@Discoverable(group: "x")`-tagged functions in the
/// same scope have inverse signatures, the suggester emits a HIGH-
/// confidence round-trip suggestion to stderr even when the function
/// names aren't in the curated naming-pair table. The attribute is a
/// no-op at runtime — the macro emits no peer declarations.
///
/// ```swift
/// struct Codec {
///     @Discoverable(group: "wire")
///     static func toBytes(_ x: Foo) -> Data { ... }
///
///     @Discoverable(group: "wire")
///     static func fromBytes(_ d: Data) -> Foo { ... }
/// }
/// ```
///
/// The discovery tool sees the matching group plus inverse signatures
/// and surfaces the pair, even though `toBytes` / `fromBytes` aren't in
/// the encode/decode-style naming table. Output goes to stderr only;
/// the generated file is unchanged (preserves regeneration-as-diff).
@attached(peer, names: arbitrary)
// swiftlint:disable:next unused_declaration - public macro; clients apply it as an attribute
public macro Discoverable(group: String? = nil) = #externalMacro(
    module: "PropertyLawMacroImpl",
    type: "DiscoverableMacro"
)
