import Foundation

/// Native BoxMaxxing 2.1.5 camera geometry. Coordinates remain unmirrored;
/// preview mirroring belongs to presentation, not pose/classifier input.
struct MoveNetPoint: Codable, Equatable, Sendable {
    var y: Double
    var x: Double
    var score: Double
}

struct MoveNetCrop: Codable, Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

enum MoveNetGeometryError: Error { case invalidDimensions, invalidKeypointCount, invalidRotation }

struct MoveNetLetterbox: Codable, Equatable, Sendable {
    let inputSize: Int
    let drawnWidth: Int
    let drawnHeight: Int
    let padX: Int
    let padY: Int
    let crop: MoveNetCrop
    let uprightWidth: Int
    let uprightHeight: Int

    /// C4602N.b/f: Float arithmetic and Kotlin roundToInt (ties toward +∞).
    init(inputSize: Int, crop: MoveNetCrop, uprightWidth: Int, uprightHeight: Int) throws {
        guard inputSize > 0, crop.width > 0, crop.height > 0,
              uprightWidth > 0, uprightHeight > 0 else { throw MoveNetGeometryError.invalidDimensions }
        self.inputSize = inputSize; self.crop = crop
        self.uprightWidth = uprightWidth; self.uprightHeight = uprightHeight
        let scale = min(Float(inputSize) / Float(crop.width), Float(inputSize) / Float(crop.height))
        drawnWidth = max(1, Self.kotlinRound(Float(crop.width) * scale))
        drawnHeight = max(1, Self.kotlinRound(Float(crop.height) * scale))
        padX = (inputSize - drawnWidth) / 2; padY = (inputSize - drawnHeight) / 2
    }

    /// C4602N.d: preserve model Float arithmetic; do not clamp to the image.
    func sourcePoint(modelY: Float, modelX: Float, score: Float) -> MoveNetPoint {
        let y = ((modelY * Float(inputSize) - Float(padY)) / Float(drawnHeight) * Float(crop.height) + Float(crop.y)) / Float(uprightHeight)
        let x = ((modelX * Float(inputSize) - Float(padX)) / Float(drawnWidth) * Float(crop.width) + Float(crop.x)) / Float(uprightWidth)
        return MoveNetPoint(y: Double(y), x: Double(x), score: Double(score))
    }

    static func kotlinRound(_ value: Float) -> Int { Int(floor(Double(value) + 0.5)) }
}

/// Native Z mapping: rawX = bx0 + ax * uprightX + bxu * uprightY.
struct MoveNetUprightMapping: Equatable, Sendable {
    let clockwiseDegrees: Int
    let bx0: Int, ax: Int, bxu: Int
    let by0: Int, ay: Int, byu: Int
    let uprightWidth: Int, uprightHeight: Int

    init(rawCrop: MoveNetCrop, clockwiseDegrees: Int) throws {
        guard rawCrop.width > 0, rawCrop.height > 0 else { throw MoveNetGeometryError.invalidDimensions }
        let degrees = ((clockwiseDegrees % 360) + 360) % 360
        self.clockwiseDegrees = degrees
        switch degrees {
        case 0: (bx0, ax, bxu, by0, ay, byu) = (rawCrop.x, 1, 0, rawCrop.y, 0, 1)
        case 90: (bx0, ax, bxu, by0, ay, byu) = (rawCrop.x, 0, 1, rawCrop.y + rawCrop.height - 1, -1, 0)
        case 180: (bx0, ax, bxu, by0, ay, byu) = (rawCrop.x + rawCrop.width - 1, -1, 0, rawCrop.y + rawCrop.height - 1, 0, -1)
        case 270: (bx0, ax, bxu, by0, ay, byu) = (rawCrop.x + rawCrop.width - 1, 0, -1, rawCrop.y, 1, 0)
        default: throw MoveNetGeometryError.invalidRotation
        }
        uprightWidth = degrees % 180 == 0 ? rawCrop.width : rawCrop.height
        uprightHeight = degrees % 180 == 0 ? rawCrop.height : rawCrop.width
    }

    func rawPoint(x: Int, y: Int) -> (x: Int, y: Int) {
        (bx0 + ax * x + bxu * y, by0 + ay * x + byu * y)
    }
}

/// C4635x.f: track a single-person crop; this is not person identification.
struct MoveNetCropTracker: Sendable {
    var enabled = true
    private(set) var failureCount = 0
    private var edges: [Float]?
    private var width = 0
    private var height = 0

    mutating func reset() { failureCount = 0; edges = nil; width = 0; height = 0 }

    mutating func crop(width: Int, height: Int) throws -> MoveNetCrop {
        guard width > 0, height > 0 else { throw MoveNetGeometryError.invalidDimensions }
        if self.width != width || self.height != height {
            self.width = width; self.height = height; edges = nil; failureCount = 0
        }
        guard enabled else { return MoveNetCrop(x: 0, y: 0, width: width, height: height) }
        if edges == nil { edges = initialEdges() }
        let rounded = edges!.map(MoveNetLetterbox.kotlinRound)
        return MoveNetCrop(x: rounded[0], y: rounded[1], width: max(1, rounded[2] - rounded[0]), height: max(1, rounded[3] - rounded[1]))
    }

    mutating func update(points: [MoveNetPoint]) throws {
        guard points.count == 17 else { throw MoveNetGeometryError.invalidKeypointCount }
        guard width > 0, height > 0 else { throw MoveNetGeometryError.invalidDimensions }
        guard enabled else { return }
        let confident = points.filter { Float($0.score) >= Float(0.3) }
        if confident.count < 6 {
            failureCount += 1
            if failureCount >= 15 { edges = initialEdges() }
            return
        }
        failureCount = 0
        var minX = Float.greatestFiniteMagnitude, minY = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude, maxY = -Float.greatestFiniteMagnitude
        for point in confident {
            let x = Float(point.x) * Float(width), y = Float(point.y) * Float(height)
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
        let half = min(max(max(maxX - minX, maxY - minY) * 1.7, Float(min(width, height)) * 0.45), Float(max(width, height))) / 2
        let x = (minX + maxX) / 2, y = (minY + maxY) / 2
        var next = [x - half, y - half, x + half, y + half]
        if let old = edges { next = zip(old, next).map { $0.0 * 0.5 + $0.1 * 0.5 } }
        edges = next
    }

    private func initialEdges() -> [Float] {
        let x = Float(width) / 2, y = Float(height) / 2, half = Float(min(width, height)) / 2
        return [x - half, y - half, x + half, y + half]
    }
}

/// N5/C3486W.d: bounded accumulated rate budget; busy frames do not consume it.
struct MoveNetFrameGate: Sendable {
    private(set) var sequence: UInt64 = 0
    private(set) var busyDrops: UInt64 = 0
    private(set) var capSkips: UInt64 = 0
    private var lastMs: Double?
    private var budgetMs = 0.0
    var maximumFPS: Double = 24
    var inferenceMaximumFPS: Double?

    init(maximumFPS: Double = 24, inferenceMaximumFPS: Double? = nil) {
        self.maximumFPS = maximumFPS; self.inferenceMaximumFPS = inferenceMaximumFPS
    }

    mutating func admit(timestampMs: Double, busy: Bool) -> Bool {
        sequence += 1
        guard timestampMs.isFinite, maximumFPS.isFinite, maximumFPS > 0 else { capSkips += 1; return false }
        var interval = 1000 / maximumFPS
        if let fps = inferenceMaximumFPS, fps.isFinite, fps > 0 { interval = max(interval, 1000 / min(60, max(20, fps))) }
        if let previous = lastMs { budgetMs = min(max(0, timestampMs - previous) + budgetMs, interval * 2) }
        else { budgetMs = interval }
        lastMs = timestampMs
        if busy { busyDrops += 1; return false }
        guard budgetMs >= interval else { capSkips += 1; return false }
        budgetMs -= interval
        return true
    }
}
