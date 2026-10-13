import Foundation
import UIKit
import Display
import AsyncDisplayKit

/// An adjustable frame over a photo: the selected area is shown with corner handles,
/// the rest of the photo is dimmed, like the crop tool in the media editor. The user
/// drags a corner to resize or the inside to move. The node spans the whole item and
/// only takes touches near the frame, so taps outside still reach the photo.
///
/// In the `.highlight` mode the node only dims the photo around the area: no outline,
/// no handles and no touches. The receiver sees this when opening a quoted region.
public final class VisualQuoteFrameNode: ASDisplayNode, UIGestureRecognizerDelegate {
    public enum Mode {
        case editable
        case highlight
    }
    
    public let mode: Mode
    private static let minimumSide: CGFloat = 44.0
    private static let handleHitRadius: CGFloat = 38.0
    private static let cornerRadius: CGFloat = 16.0
    private static let cornerSmoothing: CGFloat = 0.6
    private static let markTail: CGFloat = 0.0
    /// Fraction of the straight-ish ends of each corner curve left out of the marks.
    private static let markTrim: CGFloat = 0.35
    private static let markWidth: CGFloat = 3.0
    /// The media editor's crop tool dims with black at 0.45; the passive highlight is denser, since there is no outline to carry the contrast.
    private static let editableDimAlpha: CGFloat = 0.4
    private static let highlightDimAlpha: CGFloat = 0.65
    
    private enum DragMode {
        case move
        case corner(left: Bool, top: Bool)
    }
    
    public private(set) var region: VisualQuoteRegion
    /// Called continuously while the user drags.
    public var regionChanged: ((VisualQuoteRegion) -> Void)?
    /// Called when a drag ends.
    public var dragEnded: (() -> Void)?
    
    private var imageFrame: CGRect = CGRect()
    private var visibleBounds: CGRect = CGRect()
    private var frameRect: CGRect = CGRect()
    
    private let dimLayer = SimpleShapeLayer()
    private let borderLayer = SimpleShapeLayer()
    private let bracketsLayer = SimpleShapeLayer()
    
    private var dragMode: DragMode?
    private var dragStartRect: CGRect = CGRect()
    
    public init(region: VisualQuoteRegion, mode: Mode = .editable) {
        self.region = region
        self.mode = mode
        
        super.init()
        
        self.dimLayer.fillRule = .evenOdd
        self.dimLayer.fillColor = UIColor(white: 0.0, alpha: mode == .editable ? VisualQuoteFrameNode.editableDimAlpha : VisualQuoteFrameNode.highlightDimAlpha).cgColor
        self.layer.addSublayer(self.dimLayer)
        
        guard case .editable = mode else {
            self.isUserInteractionEnabled = false
            return
        }
        
        self.borderLayer.fillColor = nil
        self.borderLayer.strokeColor = UIColor(white: 1.0, alpha: 0.7).cgColor
        self.borderLayer.lineWidth = 1.0
        self.layer.addSublayer(self.borderLayer)
        
        self.bracketsLayer.fillColor = nil
        self.bracketsLayer.strokeColor = UIColor.white.cgColor
        self.bracketsLayer.lineWidth = VisualQuoteFrameNode.markWidth
        self.bracketsLayer.lineCap = .round
        self.layer.addSublayer(self.bracketsLayer)
    }
    
    override public func didLoad() {
        super.didLoad()
        
        guard case .editable = self.mode else {
            return
        }
        let panRecognizer = UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:)))
        panRecognizer.delegate = self
        self.view.addGestureRecognizer(panRecognizer)
    }
    
    /// `imageFrame` is the photo's on-screen frame in this node's coordinates; `visibleBounds` limits where handles may go.
    public func update(imageFrame: CGRect, visibleBounds: CGRect, region: VisualQuoteRegion, animated: Bool) {
        self.imageFrame = imageFrame
        self.visibleBounds = visibleBounds
        self.region = region
        self.setFrameRect(self.rect(for: region), animated: animated)
    }
    
    public func animateIn() {
        self.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        guard case .editable = self.mode else {
            return
        }
        self.bracketsLayer.animateSpring(from: 1.15 as NSNumber, to: 1.0 as NSNumber, keyPath: "transform.scale", duration: 0.5)
    }
    
    // MARK: - Geometry
    
    private func rect(for region: VisualQuoteRegion) -> CGRect {
        let rect = region.rect
        return CGRect(
            x: self.imageFrame.minX + rect.minX * self.imageFrame.width,
            y: self.imageFrame.minY + rect.minY * self.imageFrame.height,
            width: rect.width * self.imageFrame.width,
            height: rect.height * self.imageFrame.height
        )
    }
    
    private func region(for rect: CGRect) -> VisualQuoteRegion {
        guard self.imageFrame.width > 0.0, self.imageFrame.height > 0.0 else {
            return self.region
        }
        var region = self.region
        region.rect = CGRect(
            x: (rect.minX - self.imageFrame.minX) / self.imageFrame.width,
            y: (rect.minY - self.imageFrame.minY) / self.imageFrame.height,
            width: rect.width / self.imageFrame.width,
            height: rect.height / self.imageFrame.height
        )
        return region
    }
    
    private var allowedRect: CGRect {
        let rect = self.imageFrame.intersection(self.visibleBounds)
        return rect.isNull ? self.imageFrame : rect
    }
    
    private func setFrameRect(_ rect: CGRect, animated: Bool) {
        let previousPaths = (self.dimLayer.path, self.borderLayer.path, self.bracketsLayer.path)
        self.frameRect = rect
        
        let shape = smoothRoundedRectPath(rect, cornerRadius: VisualQuoteFrameNode.cornerRadius, smoothing: VisualQuoteFrameNode.cornerSmoothing)
        let dimPath = UIBezierPath(rect: self.imageFrame)
        dimPath.append(UIBezierPath(cgPath: shape))
        self.dimLayer.path = dimPath.cgPath
        guard case .editable = self.mode else {
            if animated, let dimFrom = previousPaths.0 {
                self.dimLayer.animate(from: dimFrom, to: self.dimLayer.path!, keyPath: "path", timingFunction: CAMediaTimingFunctionName.easeInEaseOut.rawValue, duration: 0.3)
            }
            return
        }
        self.borderLayer.path = shape
        self.bracketsLayer.path = smoothCornerMarksPath(rect, cornerRadius: VisualQuoteFrameNode.cornerRadius, smoothing: VisualQuoteFrameNode.cornerSmoothing, tail: VisualQuoteFrameNode.markTail, trim: VisualQuoteFrameNode.markTrim)
        
        if animated, let dimFrom = previousPaths.0, let borderFrom = previousPaths.1, let bracketsFrom = previousPaths.2 {
            let timing = CAMediaTimingFunctionName.easeInEaseOut.rawValue
            self.dimLayer.animate(from: dimFrom, to: self.dimLayer.path!, keyPath: "path", timingFunction: timing, duration: 0.3)
            self.borderLayer.animate(from: borderFrom, to: self.borderLayer.path!, keyPath: "path", timingFunction: timing, duration: 0.3)
            self.bracketsLayer.animate(from: bracketsFrom, to: self.bracketsLayer.path!, keyPath: "path", timingFunction: timing, duration: 0.3)
        }
    }
    
    // MARK: - Touches
    
    override public func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard case .editable = self.mode else {
            return nil
        }
        let radius = VisualQuoteFrameNode.handleHitRadius
        if self.frameRect.insetBy(dx: -radius, dy: -radius).contains(point) {
            return self.view
        }
        return nil
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return otherGestureRecognizer is UIPanGestureRecognizer
    }
    
    @objc private func panGesture(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began:
            let location = recognizer.location(in: self.view)
            self.dragStartRect = self.frameRect
            self.dragMode = self.dragMode(at: location)
        case .changed:
            guard let dragMode = self.dragMode else {
                return
            }
            let translation = recognizer.translation(in: self.view)
            let rect = self.constrained(self.dragged(self.dragStartRect, mode: dragMode, by: translation), mode: dragMode)
            self.region = self.region(for: rect)
            self.setFrameRect(rect, animated: false)
            self.regionChanged?(self.region)
        case .ended, .cancelled, .failed:
            self.dragMode = nil
            self.dragEnded?()
        default:
            break
        }
    }
    
    private func dragMode(at point: CGPoint) -> DragMode {
        let rect = self.frameRect
        // On a small frame the corner zones would swallow the inside, so shrink them to keep moving possible.
        let radius = min(VisualQuoteFrameNode.handleHitRadius, min(rect.width, rect.height) / 3.0)
        let corners: [(CGPoint, Bool, Bool)] = [
            (CGPoint(x: rect.minX, y: rect.minY), true, true),
            (CGPoint(x: rect.maxX, y: rect.minY), false, true),
            (CGPoint(x: rect.minX, y: rect.maxY), true, false),
            (CGPoint(x: rect.maxX, y: rect.maxY), false, false)
        ]
        var best: (CGFloat, DragMode) = (CGFloat.greatestFiniteMagnitude, .move)
        for (corner, left, top) in corners {
            let distance = hypot(point.x - corner.x, point.y - corner.y)
            if distance <= radius && distance < best.0 {
                best = (distance, .corner(left: left, top: top))
            }
        }
        return best.1
    }
    
    private func dragged(_ rect: CGRect, mode: DragMode, by translation: CGPoint) -> CGRect {
        switch mode {
        case .move:
            return rect.offsetBy(dx: translation.x, dy: translation.y)
        case let .corner(left, top):
            var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
            if left {
                minX = min(minX + translation.x, maxX - VisualQuoteFrameNode.minimumSide)
            } else {
                maxX = max(maxX + translation.x, minX + VisualQuoteFrameNode.minimumSide)
            }
            if top {
                minY = min(minY + translation.y, maxY - VisualQuoteFrameNode.minimumSide)
            } else {
                maxY = max(maxY + translation.y, minY + VisualQuoteFrameNode.minimumSide)
            }
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }
    
    private func constrained(_ rect: CGRect, mode: DragMode) -> CGRect {
        let bounds = self.allowedRect
        var rect = rect
        switch mode {
        case .move:
            rect.size.width = min(rect.width, bounds.width)
            rect.size.height = min(rect.height, bounds.height)
            rect.origin.x = max(bounds.minX, min(bounds.maxX - rect.width, rect.minX))
            rect.origin.y = max(bounds.minY, min(bounds.maxY - rect.height, rect.minY))
        case .corner:
            rect = rect.intersection(bounds)
            if rect.isNull {
                rect = self.dragStartRect
            }
        }
        return rect
    }
}
