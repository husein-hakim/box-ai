import Foundation
import Testing
@testable import BoxingCore

struct MoveNetPixelParityTests {
    private struct Fixture: Decodable {
        struct Vector: Decodable {
            let name: String; let width: Int; let height: Int; let rotation: Int
            let inputSize: Int; let crop: MoveNetCrop; let y: Data; let u: Data; let v: Data
            let yStride: Int; let uvStride: Int; let pixelStride: Int; let expected: Data
        }
        let cases: [Vector]
    }
    @Test func pixelsAgreeByteForByteWithOriginalARM64MachineCode() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: root.appendingPathComponent("research/boxmaxxing/port/camera/fixtures.json")))
        for v in fixture.cases {
            let mapping = try MoveNetUprightMapping(rawCrop: .init(x: 0, y: 0, width: v.width, height: v.height), clockwiseDegrees: v.rotation)
            let frame = MoveNetYUVFrame(y: .init(bytes: v.y, rowStride: v.yStride, pixelStride: v.pixelStride),
                u: .init(bytes: v.u, rowStride: v.uvStride, pixelStride: v.pixelStride),
                v: .init(bytes: v.v, rowStride: v.uvStride, pixelStride: v.pixelStride), mapping: mapping)
            let plan = try MoveNetLetterbox(inputSize: v.inputSize, crop: v.crop, uprightWidth: mapping.uprightWidth, uprightHeight: mapping.uprightHeight)
            #expect(try MoveNetYUVConverter.rgb(frame: frame, plan: plan) == v.expected, "Original native pixels: \(v.name)")
        }
    }
}
