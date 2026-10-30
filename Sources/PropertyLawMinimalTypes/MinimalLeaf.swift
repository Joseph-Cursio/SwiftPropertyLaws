/// A type ``MinimalCodableValue`` stores directly, as a case of its own.
///
/// Each conformance pairs one Swift type with one case, in both directions. The encoder and
/// decoder ask this protocol, so the pairing is written once. Before, three type switches
/// kept fourteen entries each in step by hand: the encoder's, the decoder's, and the decoder's
/// separate check for whether a type was a leaf at all.
///
/// The pairing is exact. `.int64(5)` is an `Int64` and not an `Int`, which is the distinction
/// the codec exists to keep.
protocol MinimalLeaf {
    /// The tree's case for this value.
    var minimalValue: MinimalCodableValue { get }

    /// The value, if `tree` is this type's own case; otherwise `nil`.
    init?(minimalValue tree: MinimalCodableValue)
}

extension Bool: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .bool(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .bool(payload) = tree else { return nil }
        self = payload
    }
}

extension Int: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .int(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .int(payload) = tree else { return nil }
        self = payload
    }
}

extension Int8: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .int8(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .int8(payload) = tree else { return nil }
        self = payload
    }
}

extension Int16: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .int16(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .int16(payload) = tree else { return nil }
        self = payload
    }
}

extension Int32: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .int32(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .int32(payload) = tree else { return nil }
        self = payload
    }
}

extension Int64: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .int64(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .int64(payload) = tree else { return nil }
        self = payload
    }
}

extension UInt: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .uint(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .uint(payload) = tree else { return nil }
        self = payload
    }
}

extension UInt8: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .uint8(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .uint8(payload) = tree else { return nil }
        self = payload
    }
}

extension UInt16: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .uint16(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .uint16(payload) = tree else { return nil }
        self = payload
    }
}

extension UInt32: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .uint32(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .uint32(payload) = tree else { return nil }
        self = payload
    }
}

extension UInt64: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .uint64(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .uint64(payload) = tree else { return nil }
        self = payload
    }
}

extension Float: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .float(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .float(payload) = tree else { return nil }
        self = payload
    }
}

extension Double: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .double(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .double(payload) = tree else { return nil }
        self = payload
    }
}

extension String: MinimalLeaf {
    var minimalValue: MinimalCodableValue { .string(self) }
    init?(minimalValue tree: MinimalCodableValue) {
        guard case let .string(payload) = tree else { return nil }
        self = payload
    }
}
