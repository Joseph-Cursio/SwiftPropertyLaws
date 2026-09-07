/// The counterpart to ``MinimalEncoder``, reading a ``MinimalCodableValue`` tree.
///
/// Strict about width and signedness: a value encoded as `.int64` decodes into `Int64` and
/// **not** into `Int`. Foundation's decoders convert freely between number types, which is why a
/// JSON round trip can succeed on a type whose encoding lost information.
public enum MinimalDecoder {

    /// Decodes `type` from a typed tree.
    public static func decode<T: Decodable>(_ type: T.Type, from value: MinimalCodableValue) throws -> T {
        try T(from: _Decoder(value: value, codingPath: []))
    }
}

struct MinimalDecodingError: Error, CustomStringConvertible {
    let description: String
}

struct _Decoder: Decoder {
    let value: MinimalCodableValue
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case let .dictionary(entries) = value else {
            throw MinimalDecodingError(description: "expected dictionary, found \(value.kindName)")
        }
        return KeyedDecodingContainer(_KeyedDecoding<Key>(entries: entries, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case let .array(items) = value else {
            throw MinimalDecodingError(description: "expected array, found \(value.kindName)")
        }
        return _UnkeyedDecoding(items: items, codingPath: codingPath)
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        _SingleValueDecoding(value: value, codingPath: codingPath)
    }
}

/// Reads one primitive, requiring the tree's case to match the requested type exactly.
enum _Read {
    static func primitive<T>(_ type: T.Type, from value: MinimalCodableValue, at path: [any CodingKey]) throws -> T? {
        let decoded: Any? = switch (value, type) {
        case let (.bool(v), is Bool.Type): v
        case let (.int(v), is Int.Type): v
        case let (.int8(v), is Int8.Type): v
        case let (.int16(v), is Int16.Type): v
        case let (.int32(v), is Int32.Type): v
        case let (.int64(v), is Int64.Type): v
        case let (.uint(v), is UInt.Type): v
        case let (.uint8(v), is UInt8.Type): v
        case let (.uint16(v), is UInt16.Type): v
        case let (.uint32(v), is UInt32.Type): v
        case let (.uint64(v), is UInt64.Type): v
        case let (.float(v), is Float.Type): v
        case let (.double(v), is Double.Type): v
        case let (.string(v), is String.Type): v
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
                expected \(T.self) but the value was encoded as \(value.kindName)                 at \(path.map(\.stringValue)). Foundation's decoders convert between number                 types here; this one does not, which is the point.
                """
            )
        }
        return try T(from: _Decoder(value: value, codingPath: path))
    }
}

struct _KeyedDecoding<Key: CodingKey>: KeyedDecodingContainerProtocol {
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
        try _Read.value(T.self, from: require(key), at: codingPath + [key])
    }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type, forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        guard case let .dictionary(nested) = try require(key) else {
            throw MinimalDecodingError(description: "expected dictionary at '\(key.stringValue)'")
        }
        return KeyedDecodingContainer(
            _KeyedDecoding<NestedKey>(entries: nested, codingPath: codingPath + [key])
        )
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        guard case let .array(items) = try require(key) else {
            throw MinimalDecodingError(description: "expected array at '\(key.stringValue)'")
        }
        return _UnkeyedDecoding(items: items, codingPath: codingPath + [key])
    }

    func superDecoder() throws -> any Decoder { _Decoder(value: .dictionary(entries), codingPath: codingPath) }
    func superDecoder(forKey key: Key) throws -> any Decoder {
        _Decoder(value: try require(key), codingPath: codingPath + [key])
    }
}

struct _UnkeyedDecoding: UnkeyedDecodingContainer {
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
        try _Read.value(T.self, from: try next(), at: codingPath)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        guard case let .dictionary(entries) = try next() else {
            throw MinimalDecodingError(description: "expected dictionary in unkeyed container")
        }
        return KeyedDecodingContainer(_KeyedDecoding<NestedKey>(entries: entries, codingPath: codingPath))
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        guard case let .array(nested) = try next() else {
            throw MinimalDecodingError(description: "expected array in unkeyed container")
        }
        return _UnkeyedDecoding(items: nested, codingPath: codingPath)
    }

    mutating func superDecoder() throws -> any Decoder {
        _Decoder(value: try next(), codingPath: codingPath)
    }
}

struct _SingleValueDecoding: SingleValueDecodingContainer {
    let value: MinimalCodableValue
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        if case .null = value { return true }
        return false
    }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try _Read.value(T.self, from: value, at: codingPath)
    }
}
