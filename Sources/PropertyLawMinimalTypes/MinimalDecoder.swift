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

/// Reads one primitive, requiring the tree's case to match the requested type exactly.
enum PrimitiveReading {
    static func primitive<T>(_ type: T.Type, from value: MinimalCodableValue, at path: [any CodingKey]) throws -> T? {
        let decoded: Any? = switch (value, type) {
        case let (.bool(payload), is Bool.Type): payload
        case let (.int(payload), is Int.Type): payload
        case let (.int8(payload), is Int8.Type): payload
        case let (.int16(payload), is Int16.Type): payload
        case let (.int32(payload), is Int32.Type): payload
        case let (.int64(payload), is Int64.Type): payload
        case let (.uint(payload), is UInt.Type): payload
        case let (.uint8(payload), is UInt8.Type): payload
        case let (.uint16(payload), is UInt16.Type): payload
        case let (.uint32(payload), is UInt32.Type): payload
        case let (.uint64(payload), is UInt64.Type): payload
        case let (.float(payload), is Float.Type): payload
        case let (.double(payload), is Double.Type): payload
        case let (.string(payload), is String.Type): payload
        default: nil
        }
        guard let decoded else { return nil }
        guard let typed = decoded as? T else {
            throw MinimalDecodingError(
                description: "expected \(T.self), found \(value.kindName) at \(path.map(\.stringValue))"
            )
        }
        return typed
    }

    /// Whether `T` is one of the leaf types the tree stores directly.
    ///
    /// Load-bearing: without it a mismatched primitive — asking for `Int` where the tree holds
    /// `.int64` — falls through to `T(from:)`, which asks for a single-value container, which
    /// calls back here, forever. The recursion has to stop at the leaves, and a leaf that does
    /// not match is the error this type exists to report.
    static func isLeaf<T>(_ type: T.Type) -> Bool {
        switch type {
        case is Bool.Type, is Int.Type, is Int8.Type, is Int16.Type, is Int32.Type, is Int64.Type,
             is UInt.Type, is UInt8.Type, is UInt16.Type, is UInt32.Type, is UInt64.Type,
             is Float.Type, is Double.Type, is String.Type:
            true
        default:
            false
        }
    }

    static func value<T: Decodable>(_ type: T.Type, from value: MinimalCodableValue, at path: [any CodingKey]) throws -> T {
        if let primitive = try primitive(T.self, from: value, at: path) { return primitive }
        if isLeaf(T.self) {
            throw MinimalDecodingError(
                description: """
                expected \(T.self) but the value was encoded as \(value.kindName) \
                at \(path.map(\.stringValue)). Foundation's decoders convert between \
                number types here; this one does not, which is the point.
                """
            )
        }
        return try T(from: BoxedDecoder(value: value, codingPath: path))
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
