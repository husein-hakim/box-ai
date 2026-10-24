import Foundation

struct MoveNetYUVPlane: Sendable {
    let bytes: Data
    let rowStride: Int
    let pixelStride: Int
}

struct MoveNetYUVFrame: Sendable {
    let y: MoveNetYUVPlane
    let u: MoveNetYUVPlane
    let v: MoveNetYUVPlane
    let mapping: MoveNetUprightMapping
}

enum MoveNetPixelError: Error { case invalidLayout, unsupportedPixelFormat }

/// Direct scalar translation of the supplied ARM64 YuvCrop.nativeConvert,
/// libbm_pose_cpu.so SHA256 f304ab68…541c39ca, instructions 0x91c–0xf2c.
/// This reference intentionally retains the original sparse footprint sampling,
/// integer channel averages and limited-range YUV conversion, not a substitute
/// Core Image/vImage resampler. Native execution parity remains a separate gate.
enum MoveNetYUVConverter {
    static func rgb(frame: MoveNetYUVFrame, plan: MoveNetLetterbox, maxTapsPerAxis: Int = 4) throws -> Data {
        guard maxTapsPerAxis > 0, plan.inputSize <= 4096,
              plan.uprightWidth == frame.mapping.uprightWidth,
              plan.uprightHeight == frame.mapping.uprightHeight,
              [frame.y, frame.u, frame.v].allSatisfy({ !$0.bytes.isEmpty && $0.rowStride > 0 && $0.pixelStride > 0 }),
              frame.u.rowStride == frame.v.rowStride,
              frame.u.pixelStride == frame.v.pixelStride else { throw MoveNetPixelError.invalidLayout }
        var rgb = [UInt8](repeating: 0, count: plan.inputSize * plan.inputSize * 3)
        let scaleX = Double(plan.crop.width) / Double(plan.drawnWidth)
        let scaleY = Double(plan.crop.height) / Double(plan.drawnHeight)
        for outputY in 0..<plan.inputSize {
            guard outputY >= plan.padY, outputY < plan.padY + plan.drawnHeight else { continue }
            let firstY = max(0, Int(floor(Double(outputY - plan.padY) * scaleY + Double(plan.crop.y))))
            let lowerY = Int(floor(Double(outputY - plan.padY) * scaleY + Double(plan.crop.y)))
            let lastY = min(plan.uprightHeight, max(lowerY + 1, Int(ceil(Double(outputY - plan.padY + 1) * scaleY + Double(plan.crop.y)))))
            guard lastY > firstY else { continue }
            let stepY = max(1, (lastY - firstY) / maxTapsPerAxis)
            for outputX in 0..<plan.inputSize {
                guard outputX >= plan.padX, outputX < plan.padX + plan.drawnWidth else { continue }
                let lowerX = Int(floor(Double(outputX - plan.padX) * scaleX + Double(plan.crop.x)))
                let firstX = max(0, lowerX)
                let lastX = min(plan.uprightWidth, max(lowerX + 1, Int(ceil(Double(outputX - plan.padX + 1) * scaleX + Double(plan.crop.x)))))
                guard lastX > firstX else { continue }
                let stepX = max(1, (lastX - firstX) / maxTapsPerAxis)
                var sumY = 0, sumU = 0, sumV = 0, count = 0
                for sourceY in stride(from: firstY, to: lastY, by: stepY) {
                    for sourceX in stride(from: firstX, to: lastX, by: stepX) {
                        let raw = frame.mapping.rawPoint(x: sourceX, y: sourceY)
                        let indexY = raw.y * frame.y.rowStride + raw.x * frame.y.pixelStride
                        let indexUV = (raw.y >> 1) * frame.u.rowStride + (raw.x >> 1) * frame.u.pixelStride
                        guard indexY >= 0, indexY < frame.y.bytes.count,
                              indexUV >= 0, indexUV < frame.u.bytes.count, indexUV < frame.v.bytes.count else { continue }
                        sumY += Int(frame.y.bytes[indexY]); sumU += Int(frame.u.bytes[indexUV]); sumV += Int(frame.v.bytes[indexUV]); count += 1
                    }
                }
                guard count > 0 else { continue }
                let c = 298 * max(0, sumY / count - 16) + 128
                let d = sumU / count - 128, e = sumV / count - 128
                let index = (outputY * plan.inputSize + outputX) * 3
                rgb[index] = clamp((c + 409 * e) >> 8)
                rgb[index + 1] = clamp((c - 100 * d - 208 * e) >> 8)
                rgb[index + 2] = clamp((c + 516 * d) >> 8)
            }
        }
        return Data(rgb)
    }

    private static func clamp(_ value: Int) -> UInt8 { UInt8(min(255, max(0, value))) }
}
