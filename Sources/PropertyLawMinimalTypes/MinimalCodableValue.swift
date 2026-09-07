/// The typed tree `MinimalEncoder` produces.
///
/// The point of the enum is that it keeps distinctions Foundation's encoders erase. JSON has one
/// number type, so `Int`, `Int64`, `UInt` and `Double` all encode to the same token and decode
/// back to whatever the type asked for — a round trip through JSON therefore succeeds even when
/// the encoding lost the width or the signedness. Here `.int(5)`, `.int64(5)` and `.uint(5)` are
/// three different values, so a law comparing encoded trees sees what JSON hides.
///
/// `Codable` itself so it can be used as the transport in a `CodableCodec`.
public indirect enum MinimalCodableValue: Hashable, Codable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case int8(Int8)
    case int16(Int16)
    case int32(Int32)
    case int64(Int64)
    case uint(UInt)
    case uint8(UInt8)
    case uint16(UInt16)
    case uint32(UInt32)
    case uint64(UInt64)
    case float(Float)
    case double(Double)
    case string(String)
    case array([MinimalCodableValue])
    case dictionary([String: MinimalCodableValue])
}

public extension MinimalCodableValue {

    /// A short description of the case, for failure messages that need to say *which* shape was
    /// produced rather than only that two trees differed.
    var kindName: String {
        switch self {
        case .null: "null"
        case .bool: "bool"
        case .int: "int"
        case .int8: "int8"
        case .int16: "int16"
        case .int32: "int32"
        case .int64: "int64"
        case .uint: "uint"
        case .uint8: "uint8"
        case .uint16: "uint16"
        case .uint32: "uint32"
        case .uint64: "uint64"
        case .float: "float"
        case .double: "double"
        case .string: "string"
        case .array: "array"
        case .dictionary: "dictionary"
        }
    }
}
