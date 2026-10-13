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


private func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
}

/// Cubic Bézier control points for the part of the curve after `t` (de Casteljau).
private func cubicTail(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, from t: CGFloat) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    let p01 = lerp(p0, p1, t), p12 = lerp(p1, p2, t), p23 = lerp(p2, p3, t)
    let p012 = lerp(p01, p12, t), p123 = lerp(p12, p23, t)
    return (lerp(p012, p123, t), p123, p23, p3)
}

/// Cubic Bézier control points for the part of the curve before `t`.
private func cubicHead(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint, to t: CGFloat) -> (CGPoint, CGPoint, CGPoint, CGPoint) {
    let p01 = lerp(p0, p1, t), p12 = lerp(p1, p2, t), p23 = lerp(p2, p3, t)
    let p012 = lerp(p01, p12, t), p123 = lerp(p12, p23, t)
    return (p0, p01, p012, lerp(p012, p123, t))
}

/// Appends the four corner curves of `rect` to `path`, clockwise from the top-right corner.
/// `edge` is called before each corner with the point where the corner curve starts; it either
/// draws the edge up to that point or starts a new subpath there. `extension` adds straight tails
/// along the edges on both sides of each corner (used for corner marks).
private func addSmoothCorners(to path: UIBezierPath, rect: CGRect, corner k: SmoothCorner, extension tail: CGFloat, trim: CGFloat, edge: (UIBezierPath, CGPoint) -> Void) {
    let w = rect.width
    let h = rect.height
    let r = k.radius
    let alpha = k.angleAlpha * .pi / 180.0
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: rect.minX + x, y: rect.minY + y)
    }
    // One corner: a lead-in cubic, the circular arc and a lead-out cubic. `trim` (0...1) drops that
    // fraction of the lead-in and lead-out curves, which shortens corner marks without moving the arc.
    func corner(leadIn: (CGPoint, CGPoint, CGPoint, CGPoint), arcCenter: CGPoint, startAngle: CGFloat, endAngle: CGFloat, leadOut: (CGPoint, CGPoint, CGPoint, CGPoint), tailStart: CGPoint, tailEnd: CGPoint) {
        let lead = trim > 0.0 ? cubicTail(leadIn.0, leadIn.1, leadIn.2, leadIn.3, from: trim) : leadIn
        let out = trim > 0.0 ? cubicHead(leadOut.0, leadOut.1, leadOut.2, leadOut.3, to: 1.0 - trim) : leadOut
        edge(path, tail > 0.0 ? tailStart : lead.0)
        if tail > 0.0 { path.addLine(to: lead.0) }
        path.addCurve(to: lead.3, controlPoint1: lead.1, controlPoint2: lead.2)
        path.addArc(withCenter: arcCenter, radius: r, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        path.addCurve(to: out.3, controlPoint1: out.1, controlPoint2: out.2)
        if tail > 0.0 { path.addLine(to: tailEnd) }
    }
    
    // Top-right
    corner(
        leadIn: (point(w - k.p, 0.0), point(w - k.p + k.a, 0.0), point(w - k.p + k.a + k.b, 0.0), point(w - k.p + k.a + k.b + k.c, k.d)),
        arcCenter: point(w - r, r), startAngle: -(.pi / 2.0) + alpha, endAngle: -alpha,
        leadOut: (point(w - k.d, k.p - k.a - k.b - k.c), point(w, k.p - k.a - k.b), point(w, k.p - k.a), point(w, k.p)),
        tailStart: point(w - k.p - tail, 0.0), tailEnd: point(w, k.p + tail)
    )
    // Bottom-right
    corner(
        leadIn: (point(w, h - k.p), point(w, h - k.p + k.a), point(w, h - k.p + k.a + k.b), point(w - k.d, h - k.p + k.a + k.b + k.c)),
        arcCenter: point(w - r, h - r), startAngle: alpha, endAngle: (.pi / 2.0) - alpha,
        leadOut: (point(w - k.p + k.a + k.b + k.c, h - k.d), point(w - k.p + k.a + k.b, h), point(w - k.p + k.a, h), point(w - k.p, h)),
        tailStart: point(w, h - k.p - tail), tailEnd: point(w - k.p - tail, h)
    )
    // Bottom-left
    corner(
        leadIn: (point(k.p, h), point(k.p - k.a, h), point(k.p - k.a - k.b, h), point(k.p - k.a - k.b - k.c, h - k.d)),
        arcCenter: point(r, h - r), startAngle: (.pi / 2.0) + alpha, endAngle: .pi - alpha,
        leadOut: (point(k.d, h - k.p + k.a + k.b + k.c), point(0.0, h - k.p + k.a + k.b), point(0.0, h - k.p + k.a), point(0.0, h - k.p)),
        tailStart: point(k.p + tail, h), tailEnd: point(0.0, h - k.p - tail)
    )
    // Top-left
    corner(
        leadIn: (point(0.0, k.p), point(0.0, k.p - k.a), point(0.0, k.p - k.a - k.b), point(k.d, k.p - k.a - k.b - k.c)),
        arcCenter: point(r, r), startAngle: .pi + alpha, endAngle: (3.0 * .pi / 2.0) - alpha,
        leadOut: (point(k.p - k.a - k.b - k.c, k.d), point(k.p - k.a - k.b, 0.0), point(k.p - k.a, 0.0), point(k.p, 0.0)),
        tailStart: point(0.0, k.p + tail), tailEnd: point(k.p + tail, 0.0)
    )
}

/// A closed rounded rectangle with smooth corners.
func smoothRoundedRectPath(_ rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat) -> CGPath {
    let corner = SmoothCorner(rect: rect, cornerRadius: cornerRadius, smoothing: smoothing)
    guard corner.radius > 0.0 else {
        return CGPath(rect: rect, transform: nil)
    }
    let path = UIBezierPath()
    var isFirst = true
    addSmoothCorners(to: path, rect: rect, corner: corner, extension: 0.0, trim: 0.0, edge: { path, point in
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
func smoothCornerMarksPath(_ rect: CGRect, cornerRadius: CGFloat, smoothing: CGFloat, tail: CGFloat, trim: CGFloat = 0.0) -> CGPath {
    let corner = SmoothCorner(rect: rect, cornerRadius: cornerRadius, smoothing: smoothing)
    let maxTail = max(0.0, min(rect.width, rect.height) / 2.0 - corner.p - 2.0)
    let path = UIBezierPath()
    addSmoothCorners(to: path, rect: rect, corner: corner, extension: min(tail, maxTail), trim: trim, edge: { path, point in
        path.move(to: point)
    })
    return path.cgPath
}
