import AVFoundation
import ImageIO
import UniformTypeIdentifiers

enum VideoFrames {
    static func extract(url: URL, start: Double, end: Double) async throws -> [TimedJPEG] {
        guard start.isFinite, end.isFinite, start >= 0, end > start, end - start <= 30.01 else { throw QwenError.badResponse }
        let extraction = Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 720, height: 720)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
            var frames: [TimedJPEG] = []
            // Stop just before the exclusive end so the final request remains inside the clip.
            for index in 0..<12 {
                try Task.checkCancellation()
                let seconds = start + (end - start) * Double(index) / 12
                let result = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600))
                let data = NSMutableData()
                guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw QwenError.badResponse }
                CGImageDestinationAddImage(destination, result.image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw QwenError.badResponse }
                frames.append(TimedJPEG(seconds: result.actualTime.seconds, data: data as Data))
            }
            return frames
        }
        return try await withTaskCancellationHandler { try await extraction.value } onCancel: { extraction.cancel() }
    }
}
