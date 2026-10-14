import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import PhotoResources

/// Layout constants shared by the places that draw a visual quote.
public enum VisualQuoteLayout {
    /// The fragment in a reply header, as a multiple of the title line height (a plain photo reply uses 2).
    public static let replyImageScale: CGFloat = 8.0
    
    /// How a fragment that is not square is shown in the reply header.
    public enum ReplyThumbnailStyle {
        /// A square, filled by the fragment; the long sides of a strip are cut off (plain photo replies work like this).
        case squareFill
        /// A square that shows the whole fragment, with bands in the placeholder colour.
        case squareFit
        /// The fragment's own shape: the long side is the usual size, the short side shrinks to at most a quarter of it.
        case aspect
    }
    public static let replyThumbnailStyle: ReplyThumbnailStyle = .aspect
    
    /// The thumbnail box for a fragment of `fragmentSize` pixels when the usual square side is `side` and the
    /// header can be up to `maximumWidth` wide. A landscape fragment grows in width (like a long text quote
    /// takes the whole bubble width) while its height stays within `side`; a portrait one keeps `side` as height.
    public static func replyThumbnailSize(fragmentSize: CGSize, side: CGFloat, maximumWidth: CGFloat) -> CGSize {
        switch replyThumbnailStyle {
        case .squareFill, .squareFit:
            return CGSize(width: side, height: side)
        case .aspect:
            let minimumShortSide = floor(side / 4.0)
            guard fragmentSize.width > 0.0, fragmentSize.height > 0.0 else {
                return CGSize(width: side, height: side)
            }
            if fragmentSize.width >= fragmentSize.height {
                let width = min(max(side, maximumWidth), floor(side * fragmentSize.width / fragmentSize.height))
                return CGSize(width: width, height: max(minimumShortSide, min(side, floor(width * fragmentSize.height / fragmentSize.width))))
            } else {
                return CGSize(width: max(minimumShortSide, floor(side * fragmentSize.width / fragmentSize.height)), height: side)
            }
        }
    }
}

public extension VisualQuoteRegion {
    /// The region as a gallery media subject, so the gallery can open zoomed to it.
    var galleryMediaSubject: GalleryMediaSubject {
        return .visualQuoteRegion(self.encoded())
    }
    
    init?(mediaSubject: GalleryMediaSubject?) {
        guard case let .visualQuoteRegion(data) = mediaSubject else {
            return nil
        }
        self.init(encoded: data)
    }
}

/// A `TransformImageNode` signal that draws the selected region of a photo message, cut out of
/// the best representation available locally (the thumbnail first, the full photo once downloaded).
public func visualQuoteCropImage(postbox: Postbox, message: Message, photo: TelegramMediaImage, region: VisualQuoteRegion) -> Signal<(TransformImageArguments) -> DrawingContext?, NoError> {
    let photoReference = ImageMediaReference.message(message: MessageReference(message), media: photo)
    return chatMessagePhoto(postbox: postbox, userLocation: .peer(message.id.peerId), photoReference: photoReference)
    |> map { generate -> (TransformImageArguments) -> DrawingContext? in
        return { arguments in
            guard let context = DrawingContext(size: arguments.drawingSize, scale: arguments.scale ?? 0.0, clear: true) else {
                return nil
            }
            let drawingRect = arguments.drawingRect
            
            // Decode the whole photo at a size that keeps the fragment sharp but stays cheap.
            let fragmentScale = max(1.0, 1.0 / max(region.rect.width, region.rect.height))
            let decodeSide = min(1536.0, max(arguments.boundingSize.width, arguments.boundingSize.height) * fragmentScale * UIScreenScale)
            let dimensions = (largestRepresentationForPhoto(photo)?.dimensions.cgSize ?? CGSize(width: 1.0, height: 1.0)).fitted(CGSize(width: decodeSide, height: decodeSide))
            let fullArguments = TransformImageArguments(corners: ImageCorners(), imageSize: dimensions, boundingSize: dimensions, intrinsicInsets: UIEdgeInsets())
            
            var cropped: CGImage?
            if let full = generate(fullArguments)?.generateImage()?.cgImage {
                let width = CGFloat(full.width)
                let height = CGFloat(full.height)
                let cropRect = CGRect(x: floor(region.rect.minX * width), y: floor(region.rect.minY * height), width: max(1.0, floor(region.rect.width * width)), height: max(1.0, floor(region.rect.height * height))).intersection(CGRect(x: 0.0, y: 0.0, width: width, height: height))
                if !cropRect.isNull {
                    cropped = full.cropping(to: cropRect)
                }
            }
            
            var cornerRadius: CGFloat = 0.0
            if case let .Corner(radius) = arguments.corners.topLeft {
                cornerRadius = radius
            }
            context.withFlippedContext { c in
                // Clip to the rounded shape instead of `addCorners`: that helper multiplies the colour of
                // semi-transparent pixels by their alpha once more, which darkened the corners of the
                // placeholder bands around a fragment.
                if cornerRadius > 0.0 {
                    c.addPath(UIBezierPath(roundedRect: drawingRect, cornerRadius: cornerRadius).cgPath)
                    c.clip()
                }
                c.setBlendMode(.copy)
                if let cropped {
                    let imageSize = CGSize(width: cropped.width, height: cropped.height)
                    let fittedSize: CGSize
                    switch VisualQuoteLayout.replyThumbnailStyle {
                    case .squareFit, .aspect:
                        // Show the whole fragment; when the box could not take its exact shape (short side clamped),
                        // the remainder is filled with the placeholder colour.
                        c.setFillColor((arguments.emptyColor ?? UIColor.white).cgColor)
                        c.fill(drawingRect)
                        fittedSize = imageSize.aspectFitted(drawingRect.size)
                    case .squareFill:
                        fittedSize = imageSize.aspectFilled(drawingRect.size)
                    }
                    let fittedRect = CGRect(origin: CGPoint(x: drawingRect.midX - fittedSize.width / 2.0, y: drawingRect.midY - fittedSize.height / 2.0), size: fittedSize)
                    if cornerRadius > 0.0 {
                        // When the fragment sits inside placeholder bands, round its own corners too, like the
                        // thumbnail's; when it fills the box this is the same shape as the clip above.
                        c.addPath(UIBezierPath(roundedRect: fittedRect, cornerRadius: min(cornerRadius, min(fittedRect.width, fittedRect.height) / 2.0)).cgPath)
                        c.clip()
                    }
                    c.interpolationQuality = .medium
                    c.draw(cropped, in: fittedRect)
                } else {
                    c.setFillColor((arguments.emptyColor ?? UIColor.white).cgColor)
                    c.fill(drawingRect)
                }
            }
            return context
        }
    }
}
