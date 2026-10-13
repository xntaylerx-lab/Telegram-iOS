import Foundation
import UIKit

/// A detail of a photo that a reply refers to.
///
/// All coordinates are normalized to `0...1` relative to the original image,
/// with the origin in the top-left corner, so the region does not depend on the
/// resolution of the representation (thumbnail or full-size) it is drawn on.
public struct VisualQuoteRegion: Equatable {
    public enum Kind: Equatable {
        /// A detected object; `rect` is its bounding box.
        case object
        /// No confident object under the finger; `rect` is a small area around `point`.
        case point
    }
    
    public var kind: Kind
    /// The point the user touched.
    public var point: CGPoint
    /// The highlighted area.
    public var rect: CGRect
    
    public init(kind: Kind, point: CGPoint, rect: CGRect) {
        self.kind = kind
        self.point = point
        self.rect = rect
    }
    
    /// Converts the normalized rectangle to a rectangle in a view of the given size.
    public func rect(in size: CGSize) -> CGRect {
        return CGRect(x: self.rect.minX * size.width, y: self.rect.minY * size.height, width: self.rect.width * size.width, height: self.rect.height * size.height)
    }
    
    /// Converts the normalized point to a point in a view of the given size.
    public func point(in size: CGSize) -> CGPoint {
        return CGPoint(x: self.point.x * size.width, y: self.point.y * size.height)
    }
}
