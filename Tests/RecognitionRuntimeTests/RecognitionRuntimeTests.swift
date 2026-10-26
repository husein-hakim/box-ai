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

    /// Regression: upper-body (live pads) mode once rejected every frame with
    /// invalidDimensions. Both worker modes must process consecutive frames.
    func testWorkerProcessesFramesInUpperBodyAndFullBodyModes() throws {
        let width = 128, height = 72
        let yPlane = MoveNetYUVPlane(bytes: Data((0..<(width * height)).map { UInt8(($0 * 7) % 220 + 16) }), rowStride: width, pixelStride: 1)
        let uvBytes = Data(repeating: 128, count: width * height / 2)
        let uPlane = MoveNetYUVPlane(bytes: uvBytes, rowStride: width, pixelStride: 2)
        let vPlane = MoveNetYUVPlane(bytes: Data(uvBytes.dropFirst()), rowStride: width, pixelStride: 2)
        let mapping = try MoveNetUprightMapping(rawCrop: .init(x: 0, y: 0, width: width, height: height), clockwiseDegrees: 90)
        let pixels = MoveNetYUVFrame(y: yPlane, u: uPlane, v: vPlane, mapping: mapping)
        for upperBodyOnly in [true, false] {
            let worker = MoveNetRecognitionWorker(model: .lightning, stance: .orthodox, upperBodyOnly: upperBodyOnly)
            let base = ProcessInfo.processInfo.systemUptime * 1000
            for index in 0..<6 {
                let frame = MoveNetCapturedFrame(pixels: pixels, timestampMs: base + Double(index) * 42, callbackMs: base + Double(index) * 42,
                                                 sequence: UInt64(index + 1), generation: 1, timestampSource: .captureHostClock)
                let observation = try worker.process(frame)
                XCTAssertEqual(observation.pose.count, 17)
                XCTAssertNil(observation.recoveredError)
            }
        }
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

    /// Real pixels through the review scanner: a boxer standing in guard and drifting sideways.
    /// Generate the clip with ffmpeg at /tmp/boxqa/guard.mp4 (see BUILD_STATUS); skipped when absent.
    func testClipScannerTracksABoxerInRealFootage() async throws {
        let url = URL(fileURLWithPath: "/tmp/boxqa/guard.mp4")
        try XCTSkipUnless(FileManager.default.fileExists(atPath: url.path), "No guard.mp4 fixture")
        let scan = try await ClipScanner.scan(url: url, start: 0, end: 6, stance: .orthodox, purpose: .review) { _ in }
        XCTAssertGreaterThan(scan.motion.trackedShare, 0.8)
        XCTAssertTrue(scan.motion.punches.isEmpty, "A still guard must not produce punches: \(scan.motion.moves)")
        XCTAssertGreaterThan(scan.motion.guardShare ?? 0, 0.8)
        XCTAssertGreaterThan(scan.motion.footworkRate ?? 0, 0.05)
        XCTAssertNotNil(scan.motion.stanceWidth)
        XCTAssertGreaterThanOrEqual(scan.strips.count, 4)
        for (i, strip) in scan.strips.enumerated() {
            XCTAssertLessThan(strip.jpeg.count, 120_000)
            try strip.jpeg.write(to: URL(fileURLWithPath: "/tmp/boxqa/strip-\(i).jpg"))
        }
        try scan.evidence.write(toFile: "/tmp/boxqa/evidence.txt", atomically: true, encoding: .utf8)
    }

    /// Opt-in live check of the review and style prompts against the configured model
    /// (create /tmp/boxqa/live-ai). Costs one small vision request each.
    func testLiveClipPromptsReturnValidReports() async throws {
        try XCTSkipUnless(FileManager.default.fileExists(atPath: "/tmp/boxqa/live-ai") && QwenClient().isConfigured, "Live AI check not enabled")
        let url = URL(fileURLWithPath: "/tmp/boxqa/guard.mp4")
        let scan = try await ClipScanner.scan(url: url, start: 0, end: 6, stance: .orthodox, purpose: .review) { _ in }
        let drills = ClipPrompts.drillMenu(ActivityCatalog.all)
        let reviewPrompt = ClipPrompts.review(setting: .shadowboxing, focus: "my guard", profile: "Beginner boxer, orthodox stance, goal: General boxing.", history: "", evidence: scan.evidence, drills: drills)
        let review = try await QwenClient().reviewClip(prompt: reviewPrompt, strips: scan.strips, start: 0, end: 6)
        try JSONEncoder().encode(review).write(to: URL(fileURLWithPath: "/tmp/boxqa/review.json"))
        let style = try await QwenClient().studyStyle(prompt: ClipPrompts.style(fighter: "Muhammad Ali", description: "", evidence: scan.evidence, drills: drills), strips: scan.strips, start: 0, end: 6)
        try JSONEncoder().encode(style).write(to: URL(fileURLWithPath: "/tmp/boxqa/style.json"))
    }

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
