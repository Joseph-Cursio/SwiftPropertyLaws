import Foundation
import PropertyLawKit

public extension CodableCodec {

    /// Round-trips through ``MinimalEncoder`` and ``MinimalDecoder`` rather than Foundation.
    ///
    /// Worth running beside `.json`, because JSON has one number type. `Int`, `Int64` and `UInt`
    /// all encode to the same token and decode back to whatever the destination asked for, so a
    /// JSON round trip succeeds even when the encoding lost the width or the signedness. The
    /// minimal codec keeps them apart and refuses the conversion, which turns a silent pass into
    /// a decode failure naming the case it actually found.
    ///
    /// `Data` here is transport only: the value tree is the encoding, and it is serialised so the
    /// codec fits the `(T) -> Data` shape the law suite already uses.
    static var minimal: Self {
        Self(
            identifier: "MinimalEncoder",
            encode: { value in
                let tree = try MinimalEncoder.encode(value)
                return try JSONEncoder().encode(tree)
            },
            decode: { data in
                let tree = try JSONDecoder().decode(MinimalCodableValue.self, from: data)
                return try MinimalDecoder.decode(T.self, from: tree)
            }
        )
    }
}
