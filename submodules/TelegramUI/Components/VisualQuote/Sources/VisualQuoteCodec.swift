import Foundation
import UIKit
import TelegramCore

/// Transport of a region on the wire for the prototype.
///
/// The reply header has no field for an image region. The prototype carries the region in the
/// reply's `poll_option` field (an opaque byte string the client already sends and receives as
/// `EngineMessageReplyInnerSubject.pollOption`), tagged with a magic prefix. In production this
/// would be a dedicated reply field next to `todo_item_id` / `poll_option`; see the README.
///
/// Layout: "VQ1" + kind (1 byte) + six little-endian Float32: point x, y; rect x, y, width, height.
public extension VisualQuoteRegion {
    private static let magic: [UInt8] = [0x56, 0x51, 0x31] // "VQ1"
    private static let encodedLength = 3 + 1 + 6 * 4
    
    func encoded() -> Data {
        var data = Data(VisualQuoteRegion.magic)
        data.append(self.kind == .object ? 1 : 0)
        for value in [self.point.x, self.point.y, self.rect.minX, self.rect.minY, self.rect.width, self.rect.height] {
            var bits = Float32(value).bitPattern.littleEndian
            withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
        }
        return data
    }
    
    init?(encoded data: Data) {
        guard data.count == VisualQuoteRegion.encodedLength, Array(data.prefix(3)) == VisualQuoteRegion.magic else {
            return nil
        }
        let bytes = [UInt8](data)
        var values: [CGFloat] = []
        for index in 0 ..< 6 {
            let offset = 4 + index * 4
            let bits = UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
            let value = CGFloat(Float32(bitPattern: bits))
            guard value.isFinite else {
                return nil
            }
            values.append(value)
        }
        let rect = CGRect(x: values[2], y: values[3], width: values[4], height: values[5])
        guard rect.width > 0.0, rect.height > 0.0 else {
            return nil
        }
        self.init(kind: bytes[3] == 1 ? .object : .point, point: CGPoint(x: values[0], y: values[1]), rect: rect)
    }
    
    /// The region as the reply's inner subject for sending.
    var innerSubject: EngineMessageReplyInnerSubject {
        return .pollOption(self.encoded())
    }
    
    /// The region carried by a reply's inner subject, if it is one.
    init?(innerSubject: EngineMessageReplyInnerSubject?) {
        guard case let .pollOption(data) = innerSubject else {
            return nil
        }
        self.init(encoded: data)
    }
}
