/// The counterpart to ``MinimalEncoder``, reading a ``MinimalCodableValue`` tree.
///
/// Strict about width and signedness: a value encoded as `.int64` decodes into `Int64` and
/// **not** into `Int`. Foundation's decoders convert freely between number types, which is why a
/// JSON round trip can succeed on a type whose encoding lost information.
public enum MinimalDecoder {

    /// Decodes `type` from a typed tree.
    public static func decode<T: Decodable>(_ type: T.Type, from value: MinimalCodableValue) throws -> T {
        try T(from: BoxedDecoder(value: value, codingPath: []))
    }
}

struct MinimalDecodingError: Error, CustomStringConvertible {
    let description: String
}

struct BoxedDecoder: Decoder {
    let value: MinimalCodableValue
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case let .dictionary(entries) = value else {
            throw MinimalDecodingError(description: "expected dictionary, found \(value.kindName)")
        }
        return KeyedDecodingContainer(KeyedDecoding<Key>(entries: entries, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case let .array(items) = value else {
            throw MinimalDecodingError(description: "expected array, found \(value.kindName)")
        }
        return UnkeyedDecoding(items: items, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleValueDecoding(value: value, codingPath: codingPath)
    }
}

/// Reads one value, requiring a leaf's tree case to match the requested type exactly.
enum PrimitiveReading {
    static func value<T: Decodable>(
        _ type: T.Type,
        from value: MinimalCodableValue,
        at path: [any CodingKey]
    ) throws -> T {
        // Load-bearing: a leaf has to stop here, match or not. Sent on to `T(from:)`, a
        // mismatched leaf — asking for `Int` where the tree holds `.int64` — asks for a
        // single-value container, which calls back here, forever. A leaf that does not match
        // is the error this type exists to report.
        guard let leaf = T.self as? any MinimalLeaf.Type else {
            return try T(from: BoxedDecoder(value: value, codingPath: path))
        }
        guard let decoded = leaf.init(minimalValue: value) as? T else {
            throw MinimalDecodingError(
                description: """
                expected \(T.self) but the value was encoded as \(value.kindName) \
                at \(path.map(\.stringValue)). Foundation's decoders convert between \
                number types here; this one does not, which is the point.
                """
            )
        }
        return decoded
    }
}

struct KeyedDecoding<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let entries: [String: MinimalCodableValue]
    let codingPath: [any CodingKey]
    var allKeys: [Key] { entries.keys.compactMap { Key(stringValue: $0) } }

    func contains(_ key: Key) -> Bool { entries[key.stringValue] != nil }

    private func require(_ key: Key) throws -> MinimalCodableValue {
        guard let found = entries[key.stringValue] else {
            throw MinimalDecodingError(description: "missing key '\(key.stringValue)'")
        }
        return found
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        guard let found = entries[key.stringValue] else { return true }
        if case .null = found { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try PrimitiveReading.value(T.self, from: require(key), at: codingPath + [key])
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        guard case let .dictionary(nested) = try require(key) else {
            throw MinimalDecodingError(description: "expected dictionary at '\(key.stringValue)'")
        }
        return KeyedDecodingContainer(
            KeyedDecoding<NestedKey>(entries: nested, codingPath: codingPath + [key])
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard case let .array(items) = try require(key) else {
            throw MinimalDecodingError(description: "expected array at '\(key.stringValue)'")
        }
        return UnkeyedDecoding(items: items, codingPath: codingPath + [key])
    }

    func superDecoder() throws -> any Decoder { BoxedDecoder(value: .dictionary(entries), codingPath: codingPath) }
    func superDecoder(forKey key: Key) throws -> any Decoder {
        BoxedDecoder(value: try require(key), codingPath: codingPath + [key])
    }
}

struct UnkeyedDecoding: UnkeyedDecodingContainer {
    let items: [MinimalCodableValue]
    let codingPath: [any CodingKey]
    var count: Int? { items.count }
    var isAtEnd: Bool { currentIndex >= items.count }
    var currentIndex = 0

    private mutating func next() throws -> MinimalCodableValue {
        guard !isAtEnd else { throw MinimalDecodingError(description: "unkeyed container exhausted") }
        defer { currentIndex += 1 }
        return items[currentIndex]
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return true }
        if case .null = items[currentIndex] { currentIndex += 1; return true }
        return false
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try PrimitiveReading.value(T.self, from: try next(), at: codingPath)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        guard case let .dictionary(entries) = try next() else {
            throw MinimalDecodingError(description: "expected dictionary in unkeyed container")
        }
        return KeyedDecodingContainer(KeyedDecoding<NestedKey>(entries: entries, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case let .array(nested) = try next() else {
            throw MinimalDecodingError(description: "expected array in unkeyed container")
        }
        return UnkeyedDecoding(items: nested, codingPath: codingPath)
    }

    mutating func superDecoder() throws -> any Decoder {
        BoxedDecoder(value: try next(), codingPath: codingPath)
    }
}

struct SingleValueDecoding: SingleValueDecodingContainer {
    let value: MinimalCodableValue
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        if case .null = value { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try PrimitiveReading.value(T.self, from: value, at: codingPath)
    }
}
