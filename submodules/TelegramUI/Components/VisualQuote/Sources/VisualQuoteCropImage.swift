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
    public static let replyImageScale: CGFloat = 4.5
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
            
            context.withFlippedContext { c in
                c.setBlendMode(.copy)
                if let cropped {
                    let imageSize = CGSize(width: cropped.width, height: cropped.height)
                    let fittedSize = imageSize.aspectFilled(drawingRect.size)
                    let fittedRect = CGRect(origin: CGPoint(x: drawingRect.midX - fittedSize.width / 2.0, y: drawingRect.midY - fittedSize.height / 2.0), size: fittedSize)
                    c.interpolationQuality = .medium
                    c.draw(cropped, in: fittedRect)
                } else {
                    c.setFillColor((arguments.emptyColor ?? UIColor.white).cgColor)
                    c.fill(drawingRect)
                }
            }
            addCorners(context, arguments: arguments)
            return context
        }
    }
}
