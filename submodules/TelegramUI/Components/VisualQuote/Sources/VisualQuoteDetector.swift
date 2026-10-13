import Foundation
import UIKit
import CoreImage
import SwiftSignalKit
import AccountContext
import ImageObjectSeparation

/// Result of looking for an object under the user's finger.
public enum VisualQuoteDetection {
    /// An object was found under the point; `mask` is a white-on-black mask of the object in image pixels.
    case object(region: VisualQuoteRegion, mask: CIImage)
    /// Nothing confident under the point.
    case point(region: VisualQuoteRegion)
    
    public var region: VisualQuoteRegion {
        switch self {
        case let .object(region, _):
            return region
        case let .point(region):
            return region
        }
    }
}

/// Finds the object under a touch point using the same object separation the
/// sticker editor uses (`ImageObjectSeparation`): Vision subject lifting on
/// device, a CoreML fallback model in the simulator.
public final class VisualQuoteDetector {
    private static var availabilityDisposable: Disposable?
    private static var isAvailable: Bool = false
    
    /// Makes object separation ready. In the simulator this downloads the
    /// fallback model once per launch; until it arrives, detection returns `.point`.
    public static func prepare(context: AccountContext) {
        if self.availabilityDisposable != nil {
            return
        }
        self.availabilityDisposable = (cutoutAvailability(context: context)
        |> deliverOnMainQueue).start(next: { availability in
            if case .available = availability {
                self.isAvailable = true
            }
        })
    }
    
    /// Detects the object under `normalizedPoint` (0...1, top-left origin). The completion is called on the main queue.
    public static func detect(image: UIImage, normalizedPoint: CGPoint, completion: @escaping (VisualQuoteDetection) -> Void) {
        let pointDetection = VisualQuoteDetection.point(region: self.pointRegion(at: normalizedPoint, imageSize: image.size))
        guard self.isAvailable else {
            completion(pointDetection)
            return
        }
        // The object separation's CoreML fallback (used in the simulator) scales the mask back with
        // `image.size`, which is in points. Gallery images carry the screen scale, so hand over a
        // pixel-sized copy (scale 1) to keep the mask aligned with the image.
        guard let cgImage = image.cgImage else {
            completion(pointDetection)
            return
        }
        let pixelImage = UIImage(cgImage: cgImage, scale: 1.0, orientation: image.imageOrientation)
        cutoutImage(from: pixelImage, editedImage: nil, crop: nil, target: .point(normalizedPoint), includeExtracted: false, completion: { results in
            var detection = pointDetection
            for result in results {
                guard let maskImage = result.maskImage, case let .image(uiImage, ciImage) = maskImage, let cgImage = uiImage.cgImage else {
                    continue
                }
                guard let bitmap = MaskBitmap(cgImage: cgImage, maxSide: 256) else {
                    continue
                }
                let rect = bitmap.boundingRect()
                let containsPoint = bitmap.contains(normalizedPoint: normalizedPoint)
                guard containsPoint, let rect else {
                    continue
                }
                if rect.width < 0.01 || rect.height < 0.01 {
                    continue
                }
                detection = .object(region: VisualQuoteRegion(kind: .object, point: normalizedPoint, rect: rect), mask: ciImage)
                break
            }
            Queue.mainQueue().async {
                completion(detection)
            }
        })
    }
    
    /// A square area around the point, about a fifth of the shorter side of the image.
    public static func pointRegion(at point: CGPoint, imageSize: CGSize) -> VisualQuoteRegion {
        let side = min(imageSize.width, imageSize.height) * 0.2
        let width = min(1.0, side / max(1.0, imageSize.width))
        let height = min(1.0, side / max(1.0, imageSize.height))
        var rect = CGRect(x: point.x - width / 2.0, y: point.y - height / 2.0, width: width, height: height)
        rect.origin.x = max(0.0, min(1.0 - width, rect.origin.x))
        rect.origin.y = max(0.0, min(1.0 - height, rect.origin.y))
        return VisualQuoteRegion(kind: .point, point: point, rect: rect)
    }
}

/// A downscaled 8-bit copy of a mask, used to test containment and compute a bounding box.
private struct MaskBitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    
    init?(cgImage: CGImage, maxSide: Int) {
        let scale = min(1.0, CGFloat(maxSide) / CGFloat(max(cgImage.width, cgImage.height)))
        let width = max(1, Int(CGFloat(cgImage.width) * scale))
        let height = max(1, Int(CGFloat(cgImage.height) * scale))
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(origin: CGPoint(), size: CGSize(width: width, height: height)))
            return true
        }
        if !drawn {
            return nil
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }
    
    /// Bitmap rows start at the top of the image, so a top-left normalized point maps directly.
    func contains(normalizedPoint point: CGPoint) -> Bool {
        let x = max(0, min(self.width - 1, Int(point.x * CGFloat(self.width))))
        let y = max(0, min(self.height - 1, Int(point.y * CGFloat(self.height))))
        return self.pixels[y * self.width + x] > 127
    }
    
    func boundingRect() -> CGRect? {
        var minX = self.width, minY = self.height, maxX = -1, maxY = -1
        for y in 0 ..< self.height {
            let row = y * self.width
            for x in 0 ..< self.width {
                if self.pixels[row + x] > 127 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        if maxX < 0 {
            return nil
        }
        return CGRect(
            x: CGFloat(minX) / CGFloat(self.width),
            y: CGFloat(minY) / CGFloat(self.height),
            width: CGFloat(maxX - minX + 1) / CGFloat(self.width),
            height: CGFloat(maxY - minY + 1) / CGFloat(self.height)
        )
    }
}
