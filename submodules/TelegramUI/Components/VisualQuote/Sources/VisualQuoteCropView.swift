import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import AccountContext
import PhotoResources

/// Shows the selected region of a photo message, cut out of the best representation
/// available locally (the thumbnail first, the full photo once it is downloaded).
/// The whole fragment is fitted inside the view, as in the bubble header (D-026): the rest of the
/// view shows its background colour, and the fragment keeps rounded corners of its own.
public final class VisualQuoteCropView: UIView {
    private let imageView: UIImageView
    private var disposable: Disposable?
    private var currentKey: (EngineMessage.Id, VisualQuoteRegion)?
    
    override public init(frame: CGRect) {
        self.imageView = UIImageView()
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true
        
        super.init(frame: frame)
        self.clipsToBounds = true
        self.addSubview(self.imageView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        
        let bounds = self.bounds
        var fittedSize = bounds.size
        if let image = self.imageView.image, image.size.width > 0.0, image.size.height > 0.0 {
            fittedSize = image.size.aspectFitted(bounds.size)
        }
        self.imageView.frame = CGRect(origin: CGPoint(x: floor(bounds.midX - fittedSize.width / 2.0), y: floor(bounds.midY - fittedSize.height / 2.0)), size: CGSize(width: ceil(fittedSize.width), height: ceil(fittedSize.height)))
        self.imageView.layer.cornerRadius = min(self.layer.cornerRadius, min(fittedSize.width, fittedSize.height) / 2.0)
    }
    
    public func update(context: AccountContext, message: EngineMessage, region: VisualQuoteRegion) {
        if let currentKey = self.currentKey, currentKey.0 == message.id, currentKey.1 == region {
            return
        }
        self.currentKey = (message.id, region)
        self.disposable?.dispose()
        self.imageView.image = nil
        
        guard let image = message.media.first(where: { $0 is TelegramMediaImage }) as? TelegramMediaImage, let representation = largestRepresentationForPhoto(image) else {
            return
        }
        let photoReference = ImageMediaReference.message(message: MessageReference(message._asMessage()), media: image)
        // Decode at most ~1024 px on the long side: enough for an enlarged fragment, cheap to keep.
        let decodeSize = representation.dimensions.cgSize.fitted(CGSize(width: 1024.0, height: 1024.0))
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: decodeSize, boundingSize: decodeSize, intrinsicInsets: UIEdgeInsets())
        
        self.disposable = (chatMessagePhoto(postbox: context.account.postbox, userLocation: .peer(message.id.peerId), photoReference: photoReference)
        |> map { generate -> UIImage? in
            guard let full = generate(arguments)?.generateImage(), let cgImage = full.cgImage else {
                return nil
            }
            let width = CGFloat(cgImage.width)
            let height = CGFloat(cgImage.height)
            let cropRect = CGRect(x: floor(region.rect.minX * width), y: floor(region.rect.minY * height), width: max(1.0, floor(region.rect.width * width)), height: max(1.0, floor(region.rect.height * height))).intersection(CGRect(x: 0.0, y: 0.0, width: width, height: height))
            guard !cropRect.isNull, let cropped = cgImage.cropping(to: cropRect) else {
                return nil
            }
            return UIImage(cgImage: cropped, scale: full.scale, orientation: full.imageOrientation)
        }
        |> deliverOnMainQueue).start(next: { [weak self] image in
            guard let self, let image else {
                return
            }
            self.imageView.image = image
            self.setNeedsLayout()
        })
    }
}
