/// Check a law against **every case** of a bounded input space.
///
/// The counterpart to the kit's sampled entry points. Those take a `Generator`
/// and a `TrialBudget` and report how many draws they made; this takes an
/// ``Enumeration`` and reports what fraction of the space it covered — which is
/// a statement the sampled form cannot make at any budget.
///
/// ```swift
/// // Every triple of an 8-element carrier: 512 cases, walked, not sampled.
/// try await checkEveryCase(
///     of: Every.triples(of: Every.elements("value", in: Mod8.allCases)),
///     law: "Semigroup.combineAssociativity",
///     satisfies: { triple in
///         Mod8.combine(Mod8.combine(triple.first, triple.second), triple.third)
///             == Mod8.combine(triple.first, Mod8.combine(triple.second, triple.third))
///     }
/// )
/// ```
///
/// ## This walks the whole space
///
/// There is no trial cap and no hidden default, because a cap that arrives by
/// default is exactly the "coverage is handled" impression this entry point
/// exists to stop giving. A space too large to walk is capped **explicitly**
/// with `Enumeration.prefix(_:)`, and the result then reports the shortfall:
/// `covered 1 000 of 1 048 576 cases`. A space too large to be worth capping
/// wants a `Generator` and one of the sampled entry points instead.
///
/// `options.budget` is ignored — a walk's size is a property of the space, not
/// of a budget. Everything else in `LawCheckOptions` applies as usual:
/// suppression, enforcement, and replay-environment validation.
///
/// - Returns: one `CheckResult`, carrying ``SpaceCoverage``.
/// - Throws: `PropertyLawViolation` per `options.enforcement`, and
///   `ReplayEnvironmentMismatch` if `options.expectedReplayEnvironment` diverges.
@discardableResult
public func checkEveryCase<Element: Sendable>(
    of space: Enumeration<Element>,
    law protocolLaw: String,
    tier: StrictnessTier = .strict,
    options: LawCheckOptions = LawCheckOptions(),
    satisfies property: @escaping @Sendable (Element) async throws -> Bool
) async throws -> [CheckResult] {
    try await runPropertyLawSuite(options: options) {
        [
            await EnumerationDriver.run(
                protocolLaw: protocolLaw,
                tier: tier,
                options: options,
                space: space,
                property: property
            )
        ]
    }
}
