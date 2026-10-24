import Foundation
import Testing
@testable import BoxingCore

struct MoveNetGeometryTests {
    @Test func allFourRotationsPreservePixelCoordinates() throws {
        let crop = MoveNetCrop(x: 2, y: 3, width: 4, height: 6)
        let expectations = [(0, 4, 6, 2, 3), (90, 6, 4, 2, 8), (180, 4, 6, 5, 8), (270, 6, 4, 5, 3)]
        for (degrees, width, height, x, y) in expectations {
            let m = try MoveNetUprightMapping(rawCrop: crop, clockwiseDegrees: degrees)
            #expect(m.uprightWidth == width && m.uprightHeight == height)
            #expect(m.rawPoint(x: 0, y: 0) == (x, y))
            let corners = [(0, 0), (width - 1, 0), (0, height - 1), (width - 1, height - 1)].map { m.rawPoint(x: $0, y: $1) }
            #expect(Set(corners.map { "\($0.x),\($0.y)" }) == Set(["2,3", "5,3", "2,8", "5,8"]))
        }
    }
    @Test func letterboxInversePreservesOutsideImagePoints() throws {
        let p = try MoveNetLetterbox(inputSize: 192, crop: .init(x: -100, y: 40, width: 400, height: 200), uprightWidth: 640, uprightHeight: 480)
        #expect(p.drawnWidth == 192 && p.drawnHeight == 96 && p.padX == 0 && p.padY == 48)
        let point = p.sourcePoint(modelY: 0.25, modelX: 0, score: 1)
        #expect(point.x == Double(Float(-100) / Float(640)))
        #expect(point.y == Double(Float(40) / Float(480)))
    }
    @Test func trackingCropRevertsAfterFifteenWeakFrames() throws {
        var tracker = MoveNetCropTracker()
        let initial = try tracker.crop(width: 640, height: 480)
        #expect(initial == MoveNetCrop(x: 80, y: 0, width: 480, height: 480))
        try tracker.update(points: Array(repeating: MoveNetPoint(y: 0.5, x: 0.25, score: 1), count: 17))
        #expect(try tracker.crop(width: 640, height: 480) != initial)
        for _ in 0..<15 { try tracker.update(points: Array(repeating: MoveNetPoint(y: 0, x: 0, score: 0), count: 17)) }
        #expect(try tracker.crop(width: 640, height: 480) == initial)
        #expect(try tracker.crop(width: 480, height: 640) == MoveNetCrop(x: 0, y: 80, width: 480, height: 480))
    }
    @Test func originalIntegerYUVRangeAndBlackPadding() throws {
        let mapping = try MoveNetUprightMapping(rawCrop: .init(x: 0, y: 0, width: 2, height: 2), clockwiseDegrees: 0)
        func frame(_ y: UInt8, _ u: UInt8, _ v: UInt8) -> MoveNetYUVFrame {
            .init(y: .init(bytes: Data(repeating: y, count: 4), rowStride: 2, pixelStride: 1), u: .init(bytes: Data([u]), rowStride: 1, pixelStride: 1), v: .init(bytes: Data([v]), rowStride: 1, pixelStride: 1), mapping: mapping)
        }
        let p = try MoveNetLetterbox(inputSize: 2, crop: .init(x: 0, y: 0, width: 2, height: 2), uprightWidth: 2, uprightHeight: 2)
        #expect(try MoveNetYUVConverter.rgb(frame: frame(16,128,128), plan: p) == Data(repeating: 0, count: 12))
        #expect(try MoveNetYUVConverter.rgb(frame: frame(235,128,128), plan: p) == Data(repeating: 255, count: 12))
        #expect(try MoveNetYUVConverter.rgb(frame: frame(81,90,240), plan: p) == Data([255,0,0,255,0,0,255,0,0,255,0,0]))
        let outside = try MoveNetLetterbox(inputSize: 2, crop: .init(x: -2, y: -2, width: 2, height: 2), uprightWidth: 2, uprightHeight: 2)
        #expect(try MoveNetYUVConverter.rgb(frame: frame(235,128,128), plan: outside) == Data(repeating: 0, count: 12))
    }
    @Test func busyBackpressureDoesNotQueueOrConsumeFrameBudget() {
        var gate = MoveNetFrameGate(maximumFPS: 25)
        let first = gate.admit(timestampMs: 1000, busy: false); #expect(first)
        let busy = gate.admit(timestampMs: 1040, busy: true); #expect(!busy)
        let available = gate.admit(timestampMs: 1041, busy: false); #expect(available)
        let capped = gate.admit(timestampMs: 1042, busy: false); #expect(!capped)
        #expect(gate.busyDrops == 1 && gate.capSkips == 1 && gate.sequence == 4)
    }
}
