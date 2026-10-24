import AVFoundation
import SwiftUI
import Observation

// All session configuration and start/stop operations are confined to queue.
// The preview layer only reads session; UI callbacks hop to the main actor.
final class CaptureEngine: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private let queue = DispatchQueue(label: "box.camera.capture", qos: .userInitiated)
    private var configured = false
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var captureAngle: CGFloat = 0
    private var completion: (@Sendable (URL?, String?) -> Void)?
    private let frameAdapter: MoveNetFrameAdapter?
    private var frameRotation: Int?
    private var framesEnabled = false

    init(frameAdapter: MoveNetFrameAdapter? = nil) {
        self.frameAdapter = frameAdapter
        super.init()
    }

    private func configureFrames(enabled: Bool) throws {
        guard let frameAdapter else { return }
        let quarter = ((Int((Double(captureAngle) / 90).rounded()) * 90) % 360 + 360) % 360
        guard framesEnabled != enabled || frameRotation != quarter else { return }
        try frameAdapter.configure(enabled: enabled, clockwiseDegrees: quarter)
        framesEnabled = enabled; frameRotation = quarter
    }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured {
                        self.session.beginConfiguration()
                        defer { self.session.commitConfiguration() }
                        self.session.sessionPreset = .hd1280x720
                        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { throw CaptureError.noCamera }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else { throw CaptureError.noCamera }
                        self.session.addInput(input); self.session.addOutput(self.output)
                        try self.frameAdapter?.attach(to: self.session)
                        self.output.maxRecordedDuration = CMTime(seconds: 120, preferredTimescale: 600)
                        self.output.minFreeDiskSpaceLimit = 100_000_000
                        // Sensor mounting differs between cameras and iPhone generations.
                        // Use the device's gravity-aware capture rotation, never a fixed portrait angle.
                        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
                        self.rotationCoordinator = coordinator
                        self.captureAngle = coordinator.videoRotationAngleForHorizonLevelCapture
                        self.rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak engine = self] coordinator, change in
                            let angle = change.newValue ?? coordinator.videoRotationAngleForHorizonLevelCapture
                            engine?.updateCaptureAngle(angle)
                        }
                        self.configured = true
                    }
                    try self.configureFrames(enabled: true)
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning else { throw CaptureError.noCamera }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func record(completion: @escaping @Sendable (URL?, String?) -> Void) {
        queue.async {
            guard self.session.isRunning, !self.output.isRecording else { completion(nil, "The camera is not ready. Please reopen capture."); return }
            self.applyCaptureAngle()
            self.completion = completion
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("mov")
            self.output.startRecording(to: url, recordingDelegate: self)
        }
    }
    private func updateCaptureAngle(_ angle: CGFloat) {
        queue.async {
            self.captureAngle = angle
            try? self.configureFrames(enabled: self.framesEnabled)
            if !self.output.isRecording { self.applyCaptureAngle() }
        }
    }
    private func applyCaptureAngle() {
        guard let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(captureAngle) else { return }
        connection.videoRotationAngle = captureAngle
    }
    func stopRecording() { queue.async { if self.output.isRecording { self.output.stopRecording() } } }
    func stop() {
        queue.async {
            try? self.configureFrames(enabled: false)
            if self.output.isRecording { self.output.stopRecording() }
            if self.session.isRunning { self.session.stopRunning() }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL, from connections: [AVCaptureConnection], error: Error?) {
        queue.async {
            let success = (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? (error == nil)
            self.completion?(success ? url : nil, success ? nil : "The recording could not be completed. Please try again.")
            if !success { try? FileManager.default.removeItem(at: url) }
            self.completion = nil
        }
    }
}

enum CaptureError: LocalizedError {
    case noCamera
    var errorDescription: String? { "A usable camera is not available. Camera capture needs a physical iPhone." }
}

@MainActor @Observable final class CameraController {
    @ObservationIgnored let engine = CaptureEngine()
    var ready = false
    var recording = false
    var saving = false
    var error: String?
    var notice: String?
    var denied = false
    func start() async {
        error = nil; ready = false
        let allowed = await AVCaptureDevice.requestAccess(for: .video)
        guard allowed else { denied = true; error = "Allow camera access in Settings to record practice."; return }
        do { try await engine.start(); if Task.isCancelled { engine.stop() } else { ready = true } }
        catch { self.error = error.localizedDescription }
    }
    func record(store: AppStore) {
        guard ready, !recording, !saving else { return }
        recording = true; notice = nil; error = nil
        engine.record { [weak self] url, error in
            let controller = self
            Task { @MainActor in
                defer { controller?.recording = false; controller?.saving = false }
                if let url {
                    defer { try? FileManager.default.removeItem(at: url) }
                    if await store.saveVideo(from: url, title: "Camera practice", kind: "Shadowboxing") {
                        controller?.notice = "Clip saved to Review. No AI analysis has been run."
                    } else { controller?.error = store.storageNotice }
                } else { controller?.error = error }
            }
        }
    }
    func finish() { guard recording else { return }; saving = true; engine.stopRecording() }
    func stop() { ready = false; engine.stop() }
}

final class CameraPreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.previewLayer.session = session; view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: CameraPreviewView, context: Context) { }
}

struct CameraCaptureView: View {
    let store: AppStore
    @State private var camera = CameraController()
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                BoxPageHeader(title: "See your setup.", subtitle: "Frame your whole body in clear space. Record a silent practice clip, up to 2 minutes, and review it locally.")
                CameraPreview(session: camera.engine.session)
                    .frame(height: 400)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 26, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(camera.recording ? BoxStyle.accent : BoxStyle.borderStrong, lineWidth: camera.recording ? 2 : 1) }
                    .overlay { ViewfinderCorners().padding(14).allowsHitTesting(false) }
                    .overlay(alignment: .topLeading) {
                        if camera.recording {
                            HStack(spacing: 6) {
                                Circle().fill(BoxStyle.accent).frame(width: 8, height: 8)
                                Text(camera.saving ? "Saving" : "Rec").font(.caption.weight(.bold)).textCase(.uppercase)
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.black.opacity(0.6), in: .capsule)
                            .padding(18)
                        }
                    }
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: camera.recording)
                    .accessibilityLabel("Live front camera preview")
                if camera.recording {
                    Label(camera.saving ? "Saving clip…" : "Recording · no microphone", systemImage: "record.circle").font(.subheadline.weight(.semibold)).foregroundStyle(BoxStyle.accent)
                    PrimaryButton(title: "Stop & save", symbol: "stop.fill") { camera.finish() }.disabled(camera.saving)
                } else {
                    PrimaryButton(title: "Record practice", symbol: "record.circle") { camera.record(store: store) }.disabled(!camera.ready)
                }
                if let notice = camera.notice { BoxInlineNotice(text: "\(notice)", symbol: "checkmark.circle.fill", color: BoxStyle.conditioning) }
                if let error = camera.error {
                    BoxInlineNotice(text: "\(error)", symbol: "exclamationmark.triangle", color: BoxStyle.accent)
                    if camera.denied {
                        Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    } else { Button("Retry camera") { Task { await camera.start() } }.buttonStyle(BoxSecondaryStyle()) }
                }
                Text("Recording only · Playback and notes in Review. Camera measurements are available separately in Train.").font(.caption).foregroundStyle(BoxStyle.muted)
            }.boxPage()
        }
        .boxScreen(tint: BoxStyle.coach).foregroundStyle(BoxStyle.ink)
        .navigationTitle("Record a clip").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { DismissButton().disabled(camera.recording) } }
        .interactiveDismissDisabled(camera.recording)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { camera.stop() }
            else { Task { await camera.start() } }
        }
    }
}
