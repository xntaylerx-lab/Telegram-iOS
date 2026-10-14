import Foundation
import UIKit
import TelegramCore

/// Transport of a region on the wire for the prototype.
///
/// The region uses `EngineMessageReplyInnerSubject.pollOption` only inside the composer.
/// `VisualQuoteTransport` carries these bytes in a text entity because the server discards
/// `poll_option` on photo replies. In production this would be a dedicated reply field;
/// see the README.
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
        guard bytes[3] == 0 || bytes[3] == 1 else {
            return nil
        }
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
        // Independently encoded Float32 origins and sizes can add up to slightly more than 1.
        // Allow only that rounding error, then clamp it away before cropping or zooming.
        let tolerance: CGFloat = 0.000001
        guard values.allSatisfy({ $0 >= -tolerance && $0 <= 1.0 + tolerance }),
              rect.maxX <= 1.0 + tolerance, rect.maxY <= 1.0 + tolerance else {
            return nil
        }
        let boundedRect = rect.intersection(CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0))
        guard !boundedRect.isNull, boundedRect.width > 0.0, boundedRect.height > 0.0 else {
            return nil
        }
        let point = CGPoint(x: max(0.0, min(1.0, values[0])), y: max(0.0, min(1.0, values[1])))
        self.init(kind: bytes[3] == 1 ? .object : .point, point: point, rect: boundedRect)
    }
    
    /// The region as the composer's local reply inner subject (not the wire transport).
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
