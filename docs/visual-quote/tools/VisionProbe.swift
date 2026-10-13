import Foundation
import Vision
import CoreImage
import ImageIO

// Vision probe: run inside the iOS Simulator via `simctl spawn`.
// Usage: VisionProbe <image path> <nx> <ny>   (nx, ny normalized 0...1, origin top-left)
let args = CommandLine.arguments
guard args.count >= 4, let nx = Double(args[2]), let ny = Double(args[3]) else {
    print("usage: VisionProbe <image> <nx> <ny>"); exit(2)
}
let url = URL(fileURLWithPath: args[1])
guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("cannot load image"); exit(2)
}
print("image \(cg.width)x\(cg.height)")
let handler = VNImageRequestHandler(cgImage: cg, options: [:])

func time<T>(_ label: String, _ block: () throws -> T) rethrows -> T {
    let t = CFAbsoluteTimeGetCurrent()
    let r = try block()
    print(String(format: "%@: %.0f ms", label, (CFAbsoluteTimeGetCurrent() - t) * 1000))
    return r
}

// 1. Foreground instance mask (subject lifting), iOS 17+
if #available(iOS 17.0, *) {
    let req = VNGenerateForegroundInstanceMaskRequest()
    do {
        try time("VNGenerateForegroundInstanceMaskRequest") { try handler.perform([req]) }
        if let obs = req.results?.first {
            print("instances: \(obs.allInstances.count)")
            // instance under the touch point: instanceMask is a CVPixelBuffer of UInt8 instance labels
            let mask = obs.instanceMask
            CVPixelBufferLockBaseAddress(mask, .readOnly)
            let w = CVPixelBufferGetWidth(mask), h = CVPixelBufferGetHeight(mask)
            let px = Int(nx * Double(w)), py = Int(ny * Double(h))
            let base = CVPixelBufferGetBaseAddress(mask)!.assumingMemoryBound(to: UInt8.self)
            let bpr = CVPixelBufferGetBytesPerRow(mask)
            let label = base[py * bpr + px]
            CVPixelBufferUnlockBaseAddress(mask, .readOnly)
            print("mask \(w)x\(h), label under touch (\(px),\(py)): \(label)")
            if label != 0 {
                let m = try time("generateScaledMaskForImage") { try obs.generateScaledMaskForImage(forInstances: IndexSet(integer: Int(label)), from: handler) }
                // bounding box of the instance from the scaled mask
                CVPixelBufferLockBaseAddress(m, .readOnly)
                let mw = CVPixelBufferGetWidth(m), mh = CVPixelBufferGetHeight(m), mbpr = CVPixelBufferGetBytesPerRow(m)
                let mb = CVPixelBufferGetBaseAddress(m)!.assumingMemoryBound(to: Float32.self)
                var minX = mw, minY = mh, maxX = 0, maxY = 0
                for y in 0..<mh { for x in 0..<mw { if mb[y * (mbpr / 4) + x] > 0.5 { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) } } }
                CVPixelBufferUnlockBaseAddress(m, .readOnly)
                print(String(format: "instance bbox normalized: x=%.3f y=%.3f w=%.3f h=%.3f (mask %dx%d, %@)", Double(minX)/Double(mw), Double(minY)/Double(mh), Double(maxX-minX)/Double(mw), Double(maxY-minY)/Double(mh), mw, mh, CVPixelBufferGetPixelFormatType(m) == kCVPixelFormatType_OneComponent32Float ? "float32" : "other"))
            }
        } else { print("no foreground instances") }
    } catch { print("foreground mask FAILED: \(error)") }
}

// 2. Saliency (fallback candidate), iOS 13+
let sal = VNGenerateObjectnessBasedSaliencyImageRequest()
do {
    try time("VNGenerateObjectnessBasedSaliencyImageRequest") { try handler.perform([sal]) }
    if let obs = sal.results?.first as? VNSaliencyImageObservation {
        print("salient objects: \((obs.salientObjects ?? []).map { "\($0.boundingBox)" })")
    }
} catch { print("saliency FAILED: \(error)") }

// 3. Rectangles / text detection as cheap fallbacks for screenshots
let text = VNRecognizeTextRequest(); text.recognitionLevel = .fast
do { try time("VNRecognizeTextRequest(fast)") { try handler.perform([text]) }; print("text observations: \(text.results?.count ?? 0)") } catch { print("text FAILED: \(error)") }
