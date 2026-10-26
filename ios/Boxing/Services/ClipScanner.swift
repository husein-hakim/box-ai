#if os(iOS)
import AVFoundation
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// The on-device half of clip analysis: pose-scan the segment with MoveNet,
/// measure movement, then cut a few cropped three-frame strips around the key
/// moments. Only the strips and the measured text are sent to the AI.
enum ClipScanner {
    enum Purpose: Sendable { case review, style }
    struct Result: Sendable {
        let motion: ClipMotion
        let strips: [QwenClient.ClipStrip]
        let evidence: String
    }
    enum Failure: LocalizedError {
        case unreadable, tooLong
        var errorDescription: String? {
            switch self {
            case .unreadable: String(localized: "This clip could not be read. Try exporting it again or choosing another video.")
            case .tooLong: String(localized: "Choose a shorter segment.")
            }
        }
    }

    static func maxSeconds(_ purpose: Purpose) -> Double { purpose == .review ? 30 : 60 }

    static func scan(url: URL, start: Double, end: Double, stance: BoxMaxxingJudge.Stance, purpose: Purpose,
                     progress: @escaping @Sendable (Double) -> Void) async throws -> Result {
        guard start.isFinite, end.isFinite, start >= 0, end > start + 1 else { throw Failure.unreadable }
        guard end - start <= maxSeconds(purpose) + 0.01 else { throw Failure.tooLong }
        let work = Task.detached(priority: .userInitiated) { () throws -> Result in
            let asset = AVURLAsset(url: url)
            // 1. Pose pass. 12 fps catches a punch's onset, peak and return.
            let fps = purpose == .review ? 12.0 : 10.0
            let times = stride(from: start, to: end, by: 1 / fps).map { CMTime(seconds: $0, preferredTimescale: 600) }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 640)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 0.02, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.02, preferredTimescale: 600)
            let runtime = try MoveNetRuntime(model: .thunder)
            var tracker = MoveNetCropTracker()
            var samples: [PoseSample] = []
            var boxes: [Double: CGRect] = [:]
            var done = 0
            for await item in generator.images(for: times) {
                try Task.checkCancellation()
                done += 1
                progress(Double(done) / Double(times.count))
                guard let image = try? item.image else { continue }
                let t = item.requestedTime.seconds
                let w = image.width, h = image.height
                guard let crop = try? tracker.crop(width: w, height: h),
                      let (rgb, plan) = letterbox(image, crop: crop, size: runtime.inputSize),
                      let raw = try? runtime.infer(rgb: rgb, plan: plan) else { continue }
                try? tracker.update(points: raw)
                let points: [PadPoint?] = raw.map { $0.score >= 0.3 && (0...1).contains($0.x) && (0...1).contains($0.y) ? PadPoint(x: $0.x, y: $0.y) : nil }
                samples.append(PoseSample(tMs: t * 1000, points: points, aspect: Double(w) / Double(h)))
                let seen = points.compactMap { $0 }
                if seen.count >= 6 {
                    let xs = seen.map(\.x), ys = seen.map(\.y)
                    boxes[t] = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
                }
            }
            guard !samples.isEmpty else { throw Failure.unreadable }
            let motion = try ClipMotionAnalyzer.analyze(samples, stance: stance)

            // 2. Strips around the key moments, cropped to the boxer.
            let duration = end - start
            let moments = ClipMotionAnalyzer.keyMoments(motion, duration: duration, count: purpose == .review ? 6 : 7)
            let stripGenerator = AVAssetImageGenerator(asset: asset)
            stripGenerator.appliesPreferredTrackTransform = true
            stripGenerator.maximumSize = CGSize(width: 960, height: 960)
            stripGenerator.requestedTimeToleranceBefore = CMTime(seconds: 0.03, preferredTimescale: 600)
            stripGenerator.requestedTimeToleranceAfter = CMTime(seconds: 0.03, preferredTimescale: 600)
            var strips: [QwenClient.ClipStrip] = []
            for (index, moment) in moments.enumerated() {
                try Task.checkCancellation()
                let centre = start + moment
                let panelTimes = [centre - 0.25, centre, centre + 0.3].map { min(max($0, start), end - 0.05) }
                var images: [CGImage] = []
                for time in panelTimes {
                    if let result = try? await stripGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)) { images.append(result.image) }
                }
                guard images.count == 3 else { continue }
                // Union of the boxer's boxes near these times; a wide margin for style footage (two boxers, movement).
                let near = boxes.filter { t, _ in panelTimes.contains { abs($0 - t) < 0.2 } }.map(\.value)
                let usable = motion.isUsable && !near.isEmpty
                let region = usable ? near.reduce(near[0]) { $0.union($1) } : nil
                guard let jpeg = strip(images, region: region, margin: purpose == .review ? 0.35 : 0.9, labels: panelTimes) else { continue }
                let nearby = motion.moves.filter { abs($0.seconds - moment) < 0.35 }.map { $0.action.title(stance: stance) }
                let label = String(format: "Strip %d: clip time %.1f s, %.1f s, %.1f s (left to right).", index + 1, panelTimes[0], panelTimes[1], panelTimes[2])
                    + (nearby.isEmpty ? "" : " Camera recognised near here: " + nearby.joined(separator: ", ") + ".")
                strips.append(.init(seconds: centre, label: label, jpeg: jpeg))
            }
            guard !strips.isEmpty else { throw Failure.unreadable }
            return Result(motion: motion, strips: strips, evidence: motion.evidence(stance: stance, offsetSeconds: start))
        }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }

    /// Draws the tracked crop into the model's square input exactly as the letterbox plan describes.
    private static func letterbox(_ image: CGImage, crop: MoveNetCrop, size: Int) -> (Data, MoveNetLetterbox)? {
        guard let plan = try? MoveNetLetterbox(inputSize: size, crop: crop, uprightWidth: image.width, uprightHeight: image.height),
              let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(gray: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size, height: size))
        let sx = Double(plan.drawnWidth) / Double(crop.width), sy = Double(plan.drawnHeight) / Double(crop.height)
        context.clip(to: CGRect(x: plan.padX, y: size - plan.padY - plan.drawnHeight, width: plan.drawnWidth, height: plan.drawnHeight))
        let top = Double(plan.padY) - Double(crop.y) * sy, left = Double(plan.padX) - Double(crop.x) * sx
        let w = Double(image.width) * sx, h = Double(image.height) * sy
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: left, y: Double(size) - top - h, width: w, height: h))
        guard let bytes = context.data else { return nil }
        let rgba = bytes.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var rgb = Data(count: size * size * 3)
        rgb.withUnsafeMutableBytes { out in
            let o = out.bindMemory(to: UInt8.self)
            for i in 0..<(size * size) { o[i * 3] = rgba[i * 4]; o[i * 3 + 1] = rgba[i * 4 + 1]; o[i * 3 + 2] = rgba[i * 4 + 2] }
        }
        return (rgb, plan)
    }

    /// Three panels side by side, each cropped to `region` (normalised) plus a margin, with a time label.
    private static func strip(_ images: [CGImage], region: CGRect?, margin: Double, labels: [Double]) -> Data? {
        let panelHeight = 300.0
        let crops: [CGImage] = images.compactMap { image in
            let W = Double(image.width), H = Double(image.height)
            guard let region else { return image }
            var r = region.insetBy(dx: -region.width * margin / 2 - 0.04, dy: -region.height * margin / 2 - 0.04)
            r = r.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            // Keep a portrait-ish panel so limbs at full extension stay inside.
            let minWidth = r.height * H * 0.62 / W
            if r.width < minWidth { r = r.insetBy(dx: -(minWidth - r.width) / 2, dy: 0).intersection(CGRect(x: 0, y: 0, width: 1, height: 1)) }
            return image.cropping(to: CGRect(x: r.minX * W, y: r.minY * H, width: r.width * W, height: r.height * H).integral) ?? image
        }
        guard crops.count == images.count else { return nil }
        let widths = crops.map { Double($0.width) / Double($0.height) * panelHeight }
        let gap = 6.0
        let total = widths.reduce(0, +) + gap * Double(crops.count - 1)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: total, height: panelHeight), format: format).image { ctx in
            UIColor.black.setFill(); ctx.fill(CGRect(x: 0, y: 0, width: total, height: panelHeight))
            var x = 0.0
            for (i, crop) in crops.enumerated() {
                UIImage(cgImage: crop).draw(in: CGRect(x: x, y: 0, width: widths[i], height: panelHeight))
                let text = String(format: "%.1fs", labels[i]) as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .bold), .foregroundColor: UIColor.white]
                let size = text.size(withAttributes: attributes)
                UIColor.black.withAlphaComponent(0.6).setFill()
                UIBezierPath(roundedRect: CGRect(x: x + 6, y: 6, width: size.width + 10, height: size.height + 4), cornerRadius: 4).fill()
                text.draw(at: CGPoint(x: x + 11, y: 8), withAttributes: attributes)
                x += widths[i] + gap
            }
        }
        return image.jpegData(compressionQuality: 0.6)
    }
}
#endif
