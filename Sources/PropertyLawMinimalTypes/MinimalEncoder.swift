/// An `Encoder` that keeps the type distinctions Foundation's encoders erase.
///
/// Produces a ``MinimalCodableValue`` tree rather than bytes, so `Int64` and `Int` stay
/// distinguishable. Adapted in spirit from `swift-collections`' `_CollectionsTestSupport`,
/// which takes it from the standard library's `StdlibUnittest`.
public final class MinimalEncoder {

    public init() {}

    /// Encodes `value` to a typed tree.
    public static func encode(_ value: some Encodable) throws -> MinimalCodableValue {
        let encoder = BoxedEncoder(codingPath: [])
        try value.encode(to: encoder)
        return encoder.finalize()
    }
}

/// Storage shared between an encoder and the containers it vends, so a container writing after
/// its parent has moved on is visible rather than silently dropped.
final class EncodedBox {
    var value: MinimalCodableValue = .null
    init() {}
}

final class BoxedEncoder: Encoder {
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }
    private let box = EncodedBox()

    init(codingPath: [any CodingKey]) {
        self.codingPath = codingPath
    }

    func finalize() -> MinimalCodableValue { box.value }

    func container<Key: CodingKey>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> {
        box.value = .dictionary([:])
        return KeyedEncodingContainer(KeyedContainer<Key>(codingPath: codingPath, box: box))
    }

    func unkeyedContainer() -> any UnkeyedEncodingContainer {
        box.value = .array([])
        return UnkeyedContainer(codingPath: codingPath, box: box)
    }

    func singleValueContainer() -> any SingleValueEncodingContainer {
        SingleValueContainer(codingPath: codingPath, box: box)
    }
}

/// Converts one primitive to its exact case. The whole point of the type lives here: the width
/// and signedness a value was encoded with survive into the tree.
enum PrimitiveEncoding {
    static func value(_ value: some Encodable, codingPath: [any CodingKey]) throws -> MinimalCodableValue {
        switch value {
        case let payload as Bool: .bool(payload)
        case let payload as Int: .int(payload)
        case let payload as Int8: .int8(payload)
        case let payload as Int16: .int16(payload)
        case let payload as Int32: .int32(payload)
        case let payload as Int64: .int64(payload)
        case let payload as UInt: .uint(payload)
        case let payload as UInt8: .uint8(payload)
        case let payload as UInt16: .uint16(payload)
        case let payload as UInt32: .uint32(payload)
        case let payload as UInt64: .uint64(payload)
        case let payload as Float: .float(payload)
        case let payload as Double: .double(payload)
        case let payload as String: .string(payload)
        default:
            try {
                let nested = BoxedEncoder(codingPath: codingPath)
                try value.encode(to: nested)
                return nested.finalize()
            }()
        }
    }
}

struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let codingPath: [any CodingKey]
    let box: EncodedBox

    private func store(_ encoded: MinimalCodableValue, for key: Key) {
        guard case var .dictionary(entries) = box.value else {
            preconditionFailure("MinimalEncoder: keyed container over a non-dictionary")
        }
        precondition(
            entries[key.stringValue] == nil,
            "MinimalEncoder: key '\(key.stringValue)' encoded twice into one container"
        )
        entries[key.stringValue] = encoded
        box.value = .dictionary(entries)
    }

    mutating func encodeNil(forKey key: Key) throws { store(.null, for: key) }

    mutating func encode(_ value: some Encodable, forKey key: Key) throws {
        store(try PrimitiveEncoding.value(value, codingPath: codingPath + [key]), for: key)
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type, forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = EncodedBox()
        nested.value = .dictionary([:])
        store(.dictionary([:]), for: key)
        return KeyedEncodingContainer(
            KeyedContainer<NestedKey>(codingPath: codingPath + [key], box: nested)
        )
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let nested = EncodedBox()
        nested.value = .array([])
        store(.array([]), for: key)
        return UnkeyedContainer(codingPath: codingPath + [key], box: nested)
    }

    mutating func superEncoder() -> any Encoder { BoxedEncoder(codingPath: codingPath) }
    mutating func superEncoder(forKey key: Key) -> any Encoder {
        BoxedEncoder(codingPath: codingPath + [key])
    }
}

struct UnkeyedContainer: UnkeyedEncodingContainer {
    let codingPath: [any CodingKey]
    let box: EncodedBox

    var count: Int {
        guard case let .array(items) = box.value else { return 0 }
        return items.count
    }

    private func append(_ encoded: MinimalCodableValue) {
        guard case var .array(items) = box.value else {
            preconditionFailure("MinimalEncoder: unkeyed container over a non-array")
        }
        items.append(encoded)
        box.value = .array(items)
    }

    mutating func encodeNil() throws { append(.null) }

    mutating func encode(_ value: some Encodable) throws {
        append(try PrimitiveEncoding.value(value, codingPath: codingPath))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy _: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let nested = EncodedBox()
        nested.value = .dictionary([:])
        append(.dictionary([:]))
        return KeyedEncodingContainer(KeyedContainer<NestedKey>(codingPath: codingPath, box: nested))
    }

    mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let nested = EncodedBox()
        nested.value = .array([])
        append(.array([]))
        return UnkeyedContainer(codingPath: codingPath, box: nested)
    }

    mutating func superEncoder() -> any Encoder { BoxedEncoder(codingPath: codingPath) }
}

struct SingleValueContainer: SingleValueEncodingContainer {
    let codingPath: [any CodingKey]
    let box: EncodedBox

    mutating func encodeNil() throws { box.value = .null }

    mutating func encode(_ value: some Encodable) throws {
        box.value = try PrimitiveEncoding.value(value, codingPath: codingPath)
    }
}
