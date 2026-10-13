import Foundation
import UIKit
import CoreImage
import Display
import AsyncDisplayKit
import SwiftSignalKit

/// How a detected object is highlighted.
public enum VisualQuoteHighlightStyle: Equatable {
    /// A soft white glow around the object and a light lift of the object itself.
    case glow
    /// A thin bright outline along the object's edge with a faint glow.
    case outline
}

/// Draws the current selection over a photo. The node is meant to be a subnode of
/// the image node, with the same bounds, so it zooms and pans with the photo.
public final class VisualQuoteSelectionNode: ASDisplayNode {
    private static let renderQueue = Queue(name: "VisualQuote.render")
    private static let ciContext = CIContext(options: nil)
    
    public var highlightStyle: VisualQuoteHighlightStyle {
        didSet {
            if self.highlightStyle != oldValue, let detection = self.detection, case let .object(_, mask) = detection {
                self.renderHighlight(mask: mask, animated: false)
            }
        }
    }
    
    private let highlightLayer: SimpleLayer
    private let ringLayer: SimpleShapeLayer
    
    private var size: CGSize = CGSize()
    /// Screen points per image unit when the photo is fitted to the screen; keeps the ring the same size on screen regardless of the image resolution.
    private var pointsPerUnit: CGFloat = 1.0
    
    private(set) var detection: VisualQuoteDetection?
    private var renderToken: Int = 0
    
    public init(highlightStyle: VisualQuoteHighlightStyle) {
        self.highlightStyle = highlightStyle
        self.highlightLayer = SimpleLayer()
        self.ringLayer = SimpleShapeLayer()
        
        super.init()
        
        self.isUserInteractionEnabled = false
        
        self.highlightLayer.contentsGravity = .resize
        self.highlightLayer.opacity = 0.0
        self.layer.addSublayer(self.highlightLayer)
        
        self.ringLayer.fillColor = UIColor(white: 1.0, alpha: 0.12).cgColor
        self.ringLayer.strokeColor = UIColor.white.cgColor
        self.ringLayer.shadowColor = UIColor.white.cgColor
        self.ringLayer.shadowOpacity = 0.7
        self.ringLayer.shadowOffset = CGSize()
        self.ringLayer.opacity = 0.0
        self.layer.addSublayer(self.ringLayer)
    }
    
    public func update(size: CGSize, pointsPerUnit: CGFloat) {
        self.size = size
        self.pointsPerUnit = max(0.01, pointsPerUnit)
        self.highlightLayer.frame = CGRect(origin: CGPoint(), size: size)
        if let detection = self.detection {
            self.updateRing(region: detection.region)
        }
    }
    
    /// Shows a ring at the touched point while detection is running.
    public func beginSelection(at point: CGPoint, animated: Bool) {
        let region = VisualQuoteRegion(kind: .point, point: point, rect: CGRect(origin: point, size: CGSize()))
        self.detection = .point(region: region)
        self.renderToken += 1
        self.hideHighlight(animated: animated)
        self.showRing(region: region, animated: animated)
    }
    
    public func setDetection(_ detection: VisualQuoteDetection?, animated: Bool) {
        self.detection = detection
        self.renderToken += 1
        guard let detection else {
            self.hideRing(animated: animated)
            self.hideHighlight(animated: animated)
            return
        }
        switch detection {
        case let .object(_, mask):
            self.renderHighlight(mask: mask, animated: animated)
        case let .point(region):
            self.hideHighlight(animated: animated)
            self.showRing(region: region, animated: animated)
        }
    }
    
    // MARK: - Ring
    
    private func showRing(region: VisualQuoteRegion, animated: Bool) {
        self.updateRing(region: region)
        if self.ringLayer.opacity < 1.0 {
            self.ringLayer.opacity = 1.0
            if animated {
                self.ringLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                self.ringLayer.animateSpring(from: 1.35 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.5)
            }
        }
    }
    
    private func hideRing(animated: Bool) {
        if self.ringLayer.opacity > 0.0 {
            self.ringLayer.opacity = 0.0
            if animated {
                self.ringLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
            }
        }
    }
    
    private func updateRing(region: VisualQuoteRegion) {
        let radius = 26.0 / self.pointsPerUnit
        let center = region.point(in: self.size)
        self.ringLayer.lineWidth = 2.5 / self.pointsPerUnit
        self.ringLayer.shadowRadius = 6.0 / self.pointsPerUnit
        self.ringLayer.bounds = CGRect(origin: CGPoint(), size: CGSize(width: radius * 2.0, height: radius * 2.0))
        self.ringLayer.position = center
        self.ringLayer.path = UIBezierPath(ovalIn: self.ringLayer.bounds.insetBy(dx: self.ringLayer.lineWidth / 2.0, dy: self.ringLayer.lineWidth / 2.0)).cgPath
    }
    
    // MARK: - Object highlight
    
    private func hideHighlight(animated: Bool) {
        if self.highlightLayer.opacity > 0.0 {
            self.highlightLayer.opacity = 0.0
            if animated {
                self.highlightLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.2)
            }
        }
    }
    
    private func renderHighlight(mask: CIImage, animated: Bool) {
        self.renderToken += 1
        let token = self.renderToken
        let style = self.highlightStyle
        VisualQuoteSelectionNode.renderQueue.async {
            let image = VisualQuoteSelectionNode.highlightImage(mask: mask, style: style)
            Queue.mainQueue().async { [weak self] in
                guard let self, self.renderToken == token else {
                    return
                }
                self.highlightLayer.contents = image
                self.hideRing(animated: animated)
                if self.highlightLayer.opacity < 1.0 {
                    self.highlightLayer.opacity = 1.0
                    if animated {
                        self.highlightLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.25)
                    }
                }
            }
        }
    }
    
    /// Builds the highlight picture from a white-on-black object mask. The result is at most 1024 px on the longer side; it is stretched over the photo.
    private static func highlightImage(mask: CIImage, style: VisualQuoteHighlightStyle) -> CGImage? {
        let maxSide: CGFloat = 1024.0
        let scale = min(1.0, maxSide / max(1.0, max(mask.extent.width, mask.extent.height)))
        // The mask comes out of a sharpening filter and can overshoot 0...1 in the live filter graph; clamp it before inverting or multiplying.
        let scaled = mask.transformed(by: CGAffineTransform(scaleX: scale, y: scale)).applyingFilter("CIColorClamp", parameters: [
            "inputMinComponents": CIVector(x: 0.0, y: 0.0, z: 0.0, w: 0.0),
            "inputMaxComponents": CIVector(x: 1.0, y: 1.0, z: 1.0, w: 1.0)
        ])
        let extent = scaled.extent.integral
        let unit = max(extent.width, extent.height)
        let clamped = scaled.clampedToExtent()
        
        func white(_ alpha: CGFloat, through maskImage: CIImage) -> CIImage {
            let filter = CIFilter(name: "CIBlendWithMask")!
            filter.setValue(CIImage(color: CIColor(red: 1.0, green: 1.0, blue: 1.0, alpha: alpha)).cropped(to: extent), forKey: kCIInputImageKey)
            filter.setValue(CIImage(color: CIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
            filter.setValue(maskImage.cropped(to: extent), forKey: kCIInputMaskImageKey)
            return filter.outputImage ?? CIImage.empty()
        }
        func dilate(_ image: CIImage, _ radius: CGFloat) -> CIImage {
            return image.applyingFilter("CIMorphologyMaximum", parameters: [kCIInputRadiusKey: radius])
        }
        func erode(_ image: CIImage, _ radius: CGFloat) -> CIImage {
            return image.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: radius])
        }
        func blur(_ image: CIImage, _ radius: CGFloat) -> CIImage {
            return image.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
        }
        /// Keeps `image` only where `maskImage` is black, i.e. outside the object.
        func outside(_ image: CIImage, of maskImage: CIImage) -> CIImage {
            let inverted = maskImage.applyingFilter("CIColorInvert")
            return image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: inverted])
        }
        func over(_ image: CIImage, _ background: CIImage) -> CIImage {
            return image.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: background])
        }
        
        func gamma(_ image: CIImage, _ power: CGFloat) -> CIImage {
            return image.applyingFilter("CIGammaAdjust", parameters: ["inputPower": power])
        }
        
        let softMask = blur(clamped, unit * 0.003)
        let result: CIImage
        switch style {
        case .glow:
            // A wide soft halo outside the object (gamma keeps it bright near the edge), a thin brighter rim and a light lift of the object itself.
            let halo = outside(gamma(blur(clamped, unit * 0.035), 0.6), of: softMask)
            let rim = outside(blur(dilate(clamped, unit * 0.004), unit * 0.003), of: softMask)
            result = over(white(0.1, through: softMask), over(white(0.55, through: rim), white(0.75, through: halo)))
        case .outline:
            // A thin bright stroke along the edge with a faint halo around it.
            let band = blur(outside(dilate(clamped, unit * 0.005), of: erode(clamped, unit * 0.003)), unit * 0.0015)
            let halo = outside(gamma(blur(clamped, unit * 0.03), 0.7), of: softMask)
            result = over(white(0.95, through: band), over(white(0.06, through: softMask), white(0.35, through: halo)))
        }
        guard let rendered = self.ciContext.createCGImage(result, from: extent) else {
            return nil
        }
        // Redraw into a premultiplied BGRA bitmap so Core Animation reads the alpha the way it expects.
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            return nil
        }
        context.draw(rendered, in: CGRect(origin: CGPoint(), size: CGSize(width: width, height: height)))
        return context.makeImage()
    }
}
