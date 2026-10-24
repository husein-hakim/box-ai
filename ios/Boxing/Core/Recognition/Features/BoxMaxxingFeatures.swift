import Foundation

/// Coordinates are the original tracker's body-normalized, unmirrored coordinates,
/// not MoveNet's raw source-image coordinates. See FEATURE_PORT.md for the contract.
struct BoxMaxxingFeaturePoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var score: Double
    var held: Bool = false
    var observed: Bool { score > 0 && !held }
}

struct BoxMaxxingFeaturePose: Codable, Equatable, Sendable {
    var tMs: Double
    var lost: Bool = false
    var points: [BoxMaxxingFeaturePoint]
}

struct BoxMaxxingFeatureFrame: Codable, Equatable, Sendable {
    var tMs: Double
    var f: [Float]
}

enum BoxMaxxingFeatureError: Error, Equatable {
    case pointCount(Int)
    case featureCount(Int)
    case invalidWindow
}

/// Faithful port of Hermes functions 27738–27741, rather than a new feature design.
enum BoxMaxxingFeatures {
    static let keypoints = 17
    static let featuresPerFrame = 85
    static let windowSamples = 24
    static let windowStepMs: Double = 40
    static let mirrorIndices = [0, 2, 1, 4, 3, 6, 5, 8, 7, 10, 9, 12, 11, 14, 13, 16, 15]

    static func frame(_ pose: BoxMaxxingFeaturePose, previous: BoxMaxxingFeaturePose? = nil) throws -> [Float] {
        guard pose.points.count == keypoints else { throw BoxMaxxingFeatureError.pointCount(pose.points.count) }
        if let previous, previous.points.count != keypoints {
            throw BoxMaxxingFeatureError.pointCount(previous.points.count)
        }
        var output = [Float](repeating: 0, count: featuresPerFrame)
        if pose.lost { return output }
        let dt: Double
        if let previous, !previous.lost, pose.tMs > previous.tMs {
            dt = (pose.tMs - previous.tMs) / 1_000
        } else {
            dt = 0
        }
        for index in 0..<keypoints {
            let point = pose.points[index]
            // Position is retained even for a held/unobserved point. Only a lost
            // frame zeroes every region. Replacing this with a score mask changes input.
            output[2 * index] = Float(clamp(point.x, -5, 5))
            output[2 * index + 1] = Float(clamp(point.y, -5, 5))
            if dt > 0, let previous, point.observed, previous.points[index].observed {
                let last = previous.points[index]
                // JS arithmetic is Double; Float32Array rounds at each output write.
                output[34 + 2 * index] = Float(clamp(((point.x - last.x) / dt) * 0.1, -2, 2))
                output[34 + 2 * index + 1] = Float(clamp(((point.y - last.y) / dt) * 0.1, -2, 2))
            }
            output[68 + index] = point.observed ? 1 : 0
        }
        return output
    }

    /// Nearest sample, with ties selecting the earlier frame. Missing samples
    /// outside half a step are zero; the original does not interpolate or hold.
    static func sampleWindow(_ frames: [BoxMaxxingFeatureFrame], endingAt tMs: Double,
                             samples: Int = windowSamples, stepMs: Double = windowStepMs) throws -> [Float] {
        guard samples > 0, samples <= 1_000, stepMs.isFinite, stepMs > 0 else {
            throw BoxMaxxingFeatureError.invalidWindow
        }
        for frame in frames where frame.f.count != featuresPerFrame {
            throw BoxMaxxingFeatureError.featureCount(frame.f.count)
        }
        var output = [Float](repeating: 0, count: samples * featuresPerFrame)
        guard !frames.isEmpty else { return output }
        var cursor = 0
        for index in 0..<samples {
            let target = tMs - Double(samples - 1 - index) * stepMs
            while cursor + 1 < frames.count && frames[cursor + 1].tMs <= target { cursor += 1 }
            var selected = cursor
            var distance = abs(frames[cursor].tMs - target)
            if cursor + 1 < frames.count {
                let nextDistance = abs(frames[cursor + 1].tMs - target)
                if nextDistance < distance { selected = cursor + 1; distance = nextDistance }
            }
            if distance <= stepMs / 2 {
                output.replaceSubrange(index * featuresPerFrame..<(index + 1) * featuresPerFrame, with: frames[selected].f)
            }
        }
        return output
    }

    static func mirrorWindow(_ window: [Float], samples: Int = windowSamples) throws -> [Float] {
        guard samples >= 0, window.count == samples * featuresPerFrame else {
            throw BoxMaxxingFeatureError.invalidWindow
        }
        var output = [Float](repeating: 0, count: window.count)
        for sample in 0..<samples {
            let offset = sample * featuresPerFrame
            for index in 0..<keypoints {
                let source = mirrorIndices[index]
                output[offset + 2 * index] = -window[offset + 2 * source]
                output[offset + 2 * index + 1] = window[offset + 2 * source + 1]
                output[offset + 34 + 2 * index] = -window[offset + 34 + 2 * source]
                output[offset + 34 + 2 * index + 1] = window[offset + 34 + 2 * source + 1]
                output[offset + 68 + index] = window[offset + 68 + source]
            }
        }
        return output
    }

    static func mirrorClass(_ value: String) -> String {
        if value.hasSuffix("_left") { return value.replacingOccurrences(of: "_left", with: "_right", range: value.range(of: "_left")) }
        if value.hasSuffix("_right") { return value.replacingOccurrences(of: "_right", with: "_left", range: value.range(of: "_right")) }
        return value
    }

    private static func clamp(_ value: Double, _ lower: Double, _ upper: Double) -> Double {
        // Preserve JS comparison behavior (including NaN) rather than min/max ordering.
        value < lower ? lower : (value > upper ? upper : value)
    }
}

/// Transient inference memory only. No camera frames or features are stored in SwiftData.
struct BoxMaxxingFeatureRing: Sendable {
    let keepMs: Double
    private(set) var frames: [BoxMaxxingFeatureFrame] = []
    private(set) var previous: BoxMaxxingFeaturePose?
    var size: Int { frames.count }

    init(keepMs: Double = 2_500) { self.keepMs = keepMs }

    mutating func push(_ pose: BoxMaxxingFeaturePose) throws {
        frames.append(.init(tMs: pose.tMs, f: try BoxMaxxingFeatures.frame(pose, previous: previous)))
        previous = pose
        let cutoff = pose.tMs - keepMs
        while let first = frames.first, first.tMs < cutoff { frames.removeFirst() }
    }

    func window(endingAt tMs: Double, samples: Int = BoxMaxxingFeatures.windowSamples,
                stepMs: Double = BoxMaxxingFeatures.windowStepMs) throws -> [Float] {
        try BoxMaxxingFeatures.sampleWindow(frames, endingAt: tMs, samples: samples, stepMs: stepMs)
    }

    mutating func reset() { frames.removeAll(keepingCapacity: true); previous = nil }
}
