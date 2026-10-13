import Foundation
import UIKit

/// Rounded rectangle with Figma-style corner smoothing (a "squircle"). `smoothing` is 0...1,
/// where 0 is a plain circular corner and 0.6 matches the common design default.
/// The construction follows the published Figma corner-smoothing math.
func smoothRoundedRectPath(_ rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat) -> CGPath {
    let radius = max(0.0, min(cornerRadius, min(rect.width, rect.height) / 2.0))
    guard radius > 0.0 else {
        return CGPath(rect: rect, transform: nil)
    }
    let smoothing = max(0.0, min(1.0, smoothing))
    
    // Corner parameters (see "Desperately seeking squircles", Figma).
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
    let a = 2.0 * b
    
    let w = rect.width
    let h = rect.height
    let path = UIBezierPath()
    // Points are relative to the rect's origin; the corner curves run clockwise starting on the top edge.
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: rect.minX + x, y: rect.minY + y)
    }
    
    // Top edge → top-right corner.
    // Build each corner explicitly with cubic + arc segments as in the reference implementation.
    path.move(to: point(w - p, 0.0))
    // top-right
    path.addCurve(to: point(w - p + a + b + c, d), controlPoint1: point(w - p + a, 0.0), controlPoint2: point(w - p + a + b, 0.0))
    path.addArc(withCenter: point(w - radius, radius), radius: radius, startAngle: (-90.0 + angleAlpha) * .pi / 180.0, endAngle: (-angleAlpha) * .pi / 180.0, clockwise: true)
    path.addCurve(to: point(w, p), controlPoint1: point(w, p - a - b), controlPoint2: point(w, p - a))
    // right edge → bottom-right
    path.addLine(to: point(w, h - p))
    path.addCurve(to: point(w - d, h - p + a + b + c), controlPoint1: point(w, h - p + a), controlPoint2: point(w, h - p + a + b))
    path.addArc(withCenter: point(w - radius, h - radius), radius: radius, startAngle: (angleAlpha) * .pi / 180.0, endAngle: (90.0 - angleAlpha) * .pi / 180.0, clockwise: true)
    path.addCurve(to: point(w - p, h), controlPoint1: point(w - p + a + b, h), controlPoint2: point(w - p + a, h))
    // bottom edge → bottom-left
    path.addLine(to: point(p, h))
    path.addCurve(to: point(p - a - b - c, h - d), controlPoint1: point(p - a, h), controlPoint2: point(p - a - b, h))
    path.addArc(withCenter: point(radius, h - radius), radius: radius, startAngle: (90.0 + angleAlpha) * .pi / 180.0, endAngle: (180.0 - angleAlpha) * .pi / 180.0, clockwise: true)
    path.addCurve(to: point(0.0, h - p), controlPoint1: point(0.0, h - p + a + b), controlPoint2: point(0.0, h - p + a))
    // left edge → top-left
    path.addLine(to: point(0.0, p))
    path.addCurve(to: point(d, p - a - b - c), controlPoint1: point(0.0, p - a), controlPoint2: point(0.0, p - a - b))
    path.addArc(withCenter: point(radius, radius), radius: radius, startAngle: (180.0 + angleAlpha) * .pi / 180.0, endAngle: (270.0 - angleAlpha) * .pi / 180.0, clockwise: true)
    path.addCurve(to: point(p, 0.0), controlPoint1: point(p - a - b, 0.0), controlPoint2: point(p - a, 0.0))
    path.close()
    return path.cgPath
}

/// Four short arcs sitting outside the corners of a smooth rounded rect, like the corner marks of a selection.
func cornerMarksPath(_ rect: CGRect, cornerRadius: CGFloat, offset: CGFloat, sweep: CGFloat) -> CGPath {
    let radius = max(0.0, min(cornerRadius, min(rect.width, rect.height) / 2.0)) + offset
    let path = UIBezierPath()
    let centers: [(CGPoint, CGFloat)] = [
        (CGPoint(x: rect.maxX - radius + offset, y: rect.minY + radius - offset), -45.0),
        (CGPoint(x: rect.maxX - radius + offset, y: rect.maxY - radius + offset), 45.0),
        (CGPoint(x: rect.minX + radius - offset, y: rect.maxY - radius + offset), 135.0),
        (CGPoint(x: rect.minX + radius - offset, y: rect.minY + radius - offset), 225.0)
    ]
    for (center, midAngle) in centers {
        let start = (midAngle - sweep / 2.0) * .pi / 180.0
        let end = (midAngle + sweep / 2.0) * .pi / 180.0
        path.move(to: CGPoint(x: center.x + radius * cos(start), y: center.y + radius * sin(start)))
        path.addArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
    }
    return path.cgPath
}
