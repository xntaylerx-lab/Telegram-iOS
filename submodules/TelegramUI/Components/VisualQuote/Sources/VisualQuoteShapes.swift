import Foundation
import UIKit

/// Corner geometry for a rounded rectangle with Figma-style corner smoothing (a "squircle").
/// `smoothing` is 0...1, where 0 is a plain circular corner and 0.6 is the common design default.
/// The construction follows the published Figma corner-smoothing math.
private struct SmoothCorner {
    let radius: CGFloat
    let p: CGFloat
    let a: CGFloat
    let b: CGFloat
    let c: CGFloat
    let d: CGFloat
    let angleAlpha: CGFloat
    
    init(rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat) {
        let radius = max(0.0, min(cornerRadius, min(rect.width, rect.height) / 2.0))
        let smoothing = max(0.0, min(1.0, smoothing))
        let shortestSide = min(rect.width, rect.height)
        let p = min(shortestSide / 2.0, (1.0 + smoothing) * radius)
        let arcMeasure = 90.0 * (1.0 - smoothing)
        let arcSectionLength = sin(arcMeasure / 2.0 * .pi / 180.0) * radius * sqrt(2.0)
        let angleAlpha = (90.0 - arcMeasure) / 2.0
        let p3ToP4Distance = radius * tan(angleAlpha / 2.0 * .pi / 180.0)
        let angleBeta = 45.0 * smoothing
        let c = p3ToP4Distance * cos(angleBeta * .pi / 180.0)
        let d = c * tan(angleBeta * .pi / 180.0)
        let b = (p - arcSectionLength - c - d) / 3.0
        self.radius = radius
        self.p = p
        self.a = 2.0 * b
        self.b = b
        self.c = c
        self.d = d
        self.angleAlpha = angleAlpha
    }
}

/// Appends the four corner curves of `rect` to `path`, clockwise from the top-right corner.
/// `edge` is called before each corner with the point where the corner curve starts; it either
/// draws the edge up to that point or starts a new subpath there. `extension` adds straight tails
/// along the edges on both sides of each corner (used for corner marks).
private func addSmoothCorners(to path: UIBezierPath, rect: CGRect, corner k: SmoothCorner, extension tail: CGFloat, edge: (UIBezierPath, CGPoint) -> Void) {
    let w = rect.width
    let h = rect.height
    let r = k.radius
    let alpha = k.angleAlpha * .pi / 180.0
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: rect.minX + x, y: rect.minY + y)
    }
    
    // Top-right
    edge(path, point(w - k.p - tail, 0.0))
    if tail > 0.0 { path.addLine(to: point(w - k.p, 0.0)) }
    path.addCurve(to: point(w - k.p + k.a + k.b + k.c, k.d), controlPoint1: point(w - k.p + k.a, 0.0), controlPoint2: point(w - k.p + k.a + k.b, 0.0))
    path.addArc(withCenter: point(w - r, r), radius: r, startAngle: -(.pi / 2.0) + alpha, endAngle: -alpha, clockwise: true)
    path.addCurve(to: point(w, k.p), controlPoint1: point(w, k.p - k.a - k.b), controlPoint2: point(w, k.p - k.a))
    if tail > 0.0 { path.addLine(to: point(w, k.p + tail)) }
    
    // Bottom-right
    edge(path, point(w, h - k.p - tail))
    if tail > 0.0 { path.addLine(to: point(w, h - k.p)) }
    path.addCurve(to: point(w - k.d, h - k.p + k.a + k.b + k.c), controlPoint1: point(w, h - k.p + k.a), controlPoint2: point(w, h - k.p + k.a + k.b))
    path.addArc(withCenter: point(w - r, h - r), radius: r, startAngle: alpha, endAngle: (.pi / 2.0) - alpha, clockwise: true)
    path.addCurve(to: point(w - k.p, h), controlPoint1: point(w - k.p + k.a + k.b, h), controlPoint2: point(w - k.p + k.a, h))
    if tail > 0.0 { path.addLine(to: point(w - k.p - tail, h)) }
    
    // Bottom-left
    edge(path, point(k.p + tail, h))
    if tail > 0.0 { path.addLine(to: point(k.p, h)) }
    path.addCurve(to: point(k.p - k.a - k.b - k.c, h - k.d), controlPoint1: point(k.p - k.a, h), controlPoint2: point(k.p - k.a - k.b, h))
    path.addArc(withCenter: point(r, h - r), radius: r, startAngle: (.pi / 2.0) + alpha, endAngle: .pi - alpha, clockwise: true)
    path.addCurve(to: point(0.0, h - k.p), controlPoint1: point(0.0, h - k.p + k.a + k.b), controlPoint2: point(0.0, h - k.p + k.a))
    if tail > 0.0 { path.addLine(to: point(0.0, h - k.p - tail)) }
    
    // Top-left
    edge(path, point(0.0, k.p + tail))
    if tail > 0.0 { path.addLine(to: point(0.0, k.p)) }
    path.addCurve(to: point(k.d, k.p - k.a - k.b - k.c), controlPoint1: point(0.0, k.p - k.a), controlPoint2: point(0.0, k.p - k.a - k.b))
    path.addArc(withCenter: point(r, r), radius: r, startAngle: .pi + alpha, endAngle: (3.0 * .pi / 2.0) - alpha, clockwise: true)
    path.addCurve(to: point(k.p, 0.0), controlPoint1: point(k.p - k.a - k.b, 0.0), controlPoint2: point(k.p - k.a, 0.0))
    if tail > 0.0 { path.addLine(to: point(k.p + tail, 0.0)) }
}

/// A closed rounded rectangle with smooth corners.
func smoothRoundedRectPath(_ rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat) -> CGPath {
    let corner = SmoothCorner(rect: rect, cornerRadius: cornerRadius, smoothing: smoothing)
    guard corner.radius > 0.0 else {
        return CGPath(rect: rect, transform: nil)
    }
    let path = UIBezierPath()
    var isFirst = true
    addSmoothCorners(to: path, rect: rect, corner: corner, extension: 0.0, edge: { path, point in
        if isFirst {
            path.move(to: point)
            isFirst = false
        } else {
            path.addLine(to: point)
        }
    })
    path.close()
    return path.cgPath
}

/// The four corners of the same rounded rectangle as separate open strokes, each extended by
/// `tail` points along both edges: corner marks that sit exactly on the frame's outline.
func smoothCornerMarksPath(_ rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat, tail: CGFloat) -> CGPath {
    let corner = SmoothCorner(rect: rect, cornerRadius: cornerRadius, smoothing: smoothing)
    let maxTail = max(0.0, min(rect.width, rect.height) / 2.0 - corner.p - 2.0)
    let path = UIBezierPath()
    addSmoothCorners(to: path, rect: rect, corner: corner, extension: min(tail, maxTail), edge: { path, point in
        path.move(to: point)
    })
    return path.cgPath
}
