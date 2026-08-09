import PropertyLawCore

extension ModuleScanner {

    /// One `TypeShape` per scanned type, keyed by name — the whole-module
    /// universe the Tier 3 `GeneratorResolver` recurses over. `.struct` is the
    /// default kind when only extensions were seen (the strategist falls
    /// through to `.todo` anyway in that case).
    static func makeShapes(
        from perType: [String: TypeAggregate]
    ) -> [String: TypeShape] {
        var shapes: [String: TypeShape] = [:]
        for (typeName, aggregate) in perType {
            shapes[typeName] = TypeShape(
                name: typeName,
                kind: aggregate.typeKind ?? .struct,
                inheritedTypes: aggregate.inheritedNames,
                hasUserGen: aggregate.hasUserGen,
                storedMembers: aggregate.storedMembers,
                hasUserInit: aggregate.hasUserInit,
                initializers: aggregate.initializers,
                enumCases: aggregate.enumCases,
                accessLevel: aggregate.accessLevel,
                // `typeKind` is set only from a primary declaration, so its
                // absence is exactly "we never saw this type declared".
                hasPrimaryDeclaration: aggregate.typeKind != nil
            )
        }
        return shapes
    }
}
