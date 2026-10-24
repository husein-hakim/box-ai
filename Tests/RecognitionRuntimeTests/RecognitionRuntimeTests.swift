import XCTest
import AVFoundation
@testable import Boxing

/// iOS runtime smoke checks. Synthetic pixels verify graph compatibility only;
/// these assertions are not labelled motion or recognition accuracy evidence.
final class RecognitionRuntimeTests: XCTestCase {
    func testUnchangedPoseGraphsRunWithCPUOnIOS() throws {
        for model in [MoveNetRuntime.Model.thunder, .lightning] {
            let runtime = try MoveNetRuntime(model: model)
            let n = runtime.inputSize
            let plan = try MoveNetLetterbox(inputSize: n, crop: .init(x: 0, y: 0, width: n, height: n), uprightWidth: n, uprightHeight: n)
            let rgb = Data((0..<(n * n * 3)).map { UInt8($0 % 251) })
            let start = ProcessInfo.processInfo.systemUptime
            let first = try runtime.infer(rgb: rgb, plan: plan)
            let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
            let repeated = try runtime.infer(rgb: rgb, plan: plan)
            XCTAssertEqual(first.count, 17)
            XCTAssertEqual(first, repeated)
            XCTAssertTrue(first.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.score.isFinite })
            print("POSE_RUNTIME_SMOKE model=\(model.rawValue) runtime=\(runtime.runtimeVersion) input=\(n) invokeMs=\(elapsed) points=\(first.count) synthetic=true")
        }
        let classifier = try BoxMaxxingClassifier.bundled()
        XCTAssertLessThanOrEqual(classifier.embeddedParityError, 0.001)
        print("CLASSIFIER_IOS_PARITY maxLogitError=\(classifier.embeddedParityError)")
    }
    func testCompleteKernelOnIOSMatchesRecoveredEventsAndTiming() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "fixtures", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let inputs = try XCTUnwrap(fixture["inputs"] as? [[String: Any]])
        let expected = try XCTUnwrap(fixture["outputs"] as? [[String: Any]])
        let kernel = try BoxMaxxingKernel(); try kernel.setStance(.orthodox)
        var timings: [Double] = [], events = 0, calibrations = 0
        for (input, output) in zip(inputs, expected) {
            let started = ProcessInfo.processInfo.systemUptime
            let actual = try kernel.pushJSON(JSONSerialization.data(withJSONObject: input))
            timings.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            let reference = try BoxMaxxingKernel.Sample.decode(JSONSerialization.data(withJSONObject: output))
            XCTAssertEqual(actual.punches, reference.punches)
            XCTAssertEqual(actual.status, reference.status)
            XCTAssertEqual(actual.frame.lost, reference.frame.lost)
            XCTAssertEqual(actual.frame.confident, reference.frame.confident)
            events += actual.punches.count; calibrations += actual.justCalibrated ? 1 : 0
        }
        XCTAssertEqual(events, 3); XCTAssertEqual(calibrations, 1)
        timings.sort()
        print("KERNEL_REPLAY frames=\(inputs.count) events=\(events) p50Ms=\(timings[timings.count / 2]) p95Ms=\(timings[Int(Double(timings.count - 1) * 0.95)]) synthetic=true")
    }

    #if !targetEnvironment(simulator)
    func testBoundedLiveCameraProcessingOnPhysicalIPhone() async throws {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { throw XCTSkip("Camera permission must already be granted") }
        let done = expectation(description: "150 real camera frames processed")
        let collector = CameraMetrics(done: done)
        let worker = MoveNetRecognitionWorker(stance: .orthodox)
        let adapter = MoveNetFrameAdapter(process: { frame in
            do { collector.append(try worker.process(frame)) } catch { collector.fail(String(describing: error)) }
        }, failed: { collector.fail($0) })
        let engine = CaptureEngine(frameAdapter: adapter)
        let thermalBefore = ProcessInfo.processInfo.thermalState.rawValue
        try await engine.start()
        await fulfillment(of: [done], timeout: 30)
        engine.stop()
        let result = collector.snapshot()
        XCTAssertNil(result.failure)
        XCTAssertGreaterThanOrEqual(result.latencies.count, 150)
        XCTAssertTrue(result.reliable)
        let sorted = result.latencies.sorted(), processing = result.processing.sorted()
        if !sorted.isEmpty {
            print("LIVE_CAMERA_SMOKE frames=\(sorted.count) captureToResultP50Ms=\(sorted[sorted.count / 2]) captureToResultP95Ms=\(sorted[Int(Double(sorted.count - 1) * 0.95)]) processingP50Ms=\(processing[processing.count / 2]) thermalBefore=\(thermalBefore) thermalAfter=\(ProcessInfo.processInfo.thermalState.rawValue) labelledActions=false")
        }
    }
    #endif

}

#if !targetEnvironment(simulator)
private final class CameraMetrics: @unchecked Sendable {
    struct Snapshot { var latencies: [Double] = []; var processing: [Double] = []; var failure: String?; var reliable = true }
    private let lock = NSLock()
    private var value = Snapshot()
    private var fulfilled = false
    private let done: XCTestExpectation
    init(done: XCTestExpectation) { self.done = done }
    func append(_ observation: MoveNetRecognitionWorker.Observation) {
        lock.lock(); defer { lock.unlock() }
        guard !fulfilled else { return }
        value.latencies.append(observation.finishedMs - observation.captureMs)
        value.processing.append(observation.processingMs)
        value.reliable = value.reliable && observation.timingReliable
        if value.latencies.count >= 150 { fulfilled = true; done.fulfill() }
    }
    func fail(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        value.failure = message
        if !fulfilled { fulfilled = true; done.fulfill() }
    }
    func snapshot() -> Snapshot { lock.lock(); defer { lock.unlock() }; return value }
}
#endif
