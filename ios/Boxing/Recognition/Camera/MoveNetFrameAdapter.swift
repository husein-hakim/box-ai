#if os(iOS)
import AVFoundation
import Foundation

struct MoveNetCapturedFrame: Sendable {
    let pixels: MoveNetYUVFrame
    let timestampMs: Double
    let callbackMs: Double
    let sequence: UInt64
    let generation: UInt64
    let timestampSource: TimestampSource
    enum TimestampSource: String, Sendable { case captureHostClock, callbackFallback }
}

/// A video-data output for the existing AVCaptureSession. The owner configures
/// camera inputs/preview and calls attach inside its configuration transaction.
/// One copied frame can be in flight; busy and capped frames are discarded.
/// No camera frame is persisted, and no result implies a detected punch.
final class MoveNetFrameAdapter: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let output = AVCaptureVideoDataOutput()
    private let deliveryQueue = DispatchQueue(label: "box.recognition.frames", qos: .userInitiated)
    private let inferenceQueue = DispatchQueue(label: "box.recognition.inference", qos: .userInitiated)
    private let lock = NSLock()
    private var busy = false
    private var enabled = false
    private var generation: UInt64 = 0
    private var clockwiseDegrees = 0
    private var gate = MoveNetFrameGate()
    private let process: @Sendable (MoveNetCapturedFrame) throws -> Void
    private let failed: @Sendable (String) -> Void

    init(process: @escaping @Sendable (MoveNetCapturedFrame) throws -> Void, failed: @escaping @Sendable (String) -> Void) {
        self.process = process; self.failed = failed
        super.init()
        output.alwaysDiscardsLateVideoFrames = true
        // Original converter is limited-range BT.601; reject full-range inputs
        // rather than quietly feeding a different pixel distribution.
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.setSampleBufferDelegate(self, queue: deliveryQueue)
    }

    func isCurrent(generation: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return enabled && self.generation == generation
    }

    func attach(to session: AVCaptureSession) throws {
        guard session.canAddOutput(output) else { throw MoveNetPixelError.invalidLayout }
        session.addOutput(output)
        if let connection = output.connection(with: .video) {
            connection.automaticallyAdjustsVideoMirroring = false
            if connection.isVideoMirroringSupported { connection.isVideoMirrored = false }
            if connection.isVideoRotationAngleSupported(0) { connection.videoRotationAngle = 0 }
        }
    }

    /// Raw-buffer → upright rotation is supplied by the camera owner using its
    /// RotationCoordinator. Only quarter turns match the recovered native API.
    func configure(enabled: Bool, clockwiseDegrees: Int, maximumFPS: Double = 24, inferenceMaximumFPS: Double? = nil) throws {
        guard [0, 90, 180, 270].contains(clockwiseDegrees), maximumFPS.isFinite, maximumFPS > 0 else { throw MoveNetGeometryError.invalidRotation }
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled; self.clockwiseDegrees = clockwiseDegrees
        generation += 1
        gate = MoveNetFrameGate(maximumFPS: maximumFPS, inferenceMaximumFPS: inferenceMaximumFPS)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let callbackMs = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock())) * 1000
        let capturedMs = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000
        let recognizedClock = capturedMs.isFinite && capturedMs > 0 && abs(callbackMs - capturedMs) <= 2000
        let timestamp = recognizedClock ? capturedMs : callbackMs
        lock.lock()
        guard enabled, gate.admit(timestampMs: timestamp, busy: busy) else { lock.unlock(); return }
        busy = true
        let rotation = clockwiseDegrees, generation = self.generation, sequence = gate.sequence
        lock.unlock()
        do {
            guard let image = CMSampleBufferGetImageBuffer(sampleBuffer) else { throw MoveNetPixelError.invalidLayout }
            let copied = try Self.copyVideoRange(image, rotation: rotation)
            let frame = MoveNetCapturedFrame(pixels: copied, timestampMs: timestamp, callbackMs: callbackMs, sequence: sequence, generation: generation, timestampSource: recognizedClock ? .captureHostClock : .callbackFallback)
            inferenceQueue.async {
                defer { self.lock.lock(); self.busy = false; self.lock.unlock() }
                self.lock.lock(); let stillCurrent = self.enabled && self.generation == frame.generation; self.lock.unlock()
                guard stillCurrent else { return }
                do { try self.process(frame) } catch {
                    if self.isCurrent(generation: frame.generation) { self.failed(String(describing: error)) }
                }
            }
        } catch {
            lock.lock(); busy = false; lock.unlock()
            if isCurrent(generation: generation) { failed(String(describing: error)) }
        }
    }

    private static func copyVideoRange(_ buffer: CVPixelBuffer, rotation: Int) throws -> MoveNetYUVFrame {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
              CVPixelBufferGetPlaneCount(buffer) == 2 else { throw MoveNetPixelError.unsupportedPixelFormat }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let y = CVPixelBufferGetBaseAddressOfPlane(buffer, 0), let uv = CVPixelBufferGetBaseAddressOfPlane(buffer, 1) else { throw MoveNetPixelError.invalidLayout }
        let yStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0), uvStride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 1)
        let yCount = yStride * CVPixelBufferGetHeightOfPlane(buffer, 0), uvCount = uvStride * CVPixelBufferGetHeightOfPlane(buffer, 1)
        guard yCount > 0, uvCount > 1 else { throw MoveNetPixelError.invalidLayout }
        // Two independent views preserve original Y/U/V byte-offset semantics.
        let yBytes = Data(bytes: y, count: yCount), uBytes = Data(bytes: uv, count: uvCount)
        let vBytes = Data(bytes: uv.advanced(by: 1), count: uvCount - 1)
        let raw = MoveNetCrop(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        return MoveNetYUVFrame(y: MoveNetYUVPlane(bytes: yBytes, rowStride: yStride, pixelStride: 1), u: MoveNetYUVPlane(bytes: uBytes, rowStride: uvStride, pixelStride: 2), v: MoveNetYUVPlane(bytes: vBytes, rowStride: uvStride, pixelStride: 2), mapping: try MoveNetUprightMapping(rawCrop: raw, clockwiseDegrees: rotation))
    }
}
#endif
