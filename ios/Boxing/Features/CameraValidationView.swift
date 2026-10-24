import AVFoundation
import Observation
import SwiftUI

private final class RecognitionRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var sample: (@Sendable (MoveNetRecognitionWorker.Observation) -> Void)?
    private var failure: (@Sendable (String) -> Void)?
    func set(sample: @escaping @Sendable (MoveNetRecognitionWorker.Observation) -> Void, failure: @escaping @Sendable (String) -> Void) {
        lock.lock(); defer { lock.unlock() }; self.sample = sample; self.failure = failure
    }
    func deliver(_ value: MoveNetRecognitionWorker.Observation) { lock.lock(); let callback = sample; lock.unlock(); callback?(value) }
    func fail(_ value: String) { lock.lock(); let callback = failure; lock.unlock(); callback?(value) }
}

@MainActor @Observable private final class CameraValidationController {
    @ObservationIgnored let engine: CaptureEngine
    @ObservationIgnored private let adapter: MoveNetFrameAdapter
    @ObservationIgnored private var seen: [String: Double] = [:]
    @ObservationIgnored private var generation: UInt64?
    let stance: BoxMaxxingJudge.Stance
    var active = false
    var ready = false
    var recording = false
    var saving = false
    var error: String?
    var notice: String?
    var tracking = "Starting camera…"
    var observed = "No straight punch observed"
    var latencyMs: Double?
    var received = 0

    init(stance: BoxMaxxingJudge.Stance) {
        self.stance = stance
        let relay = RecognitionRelay(), worker = MoveNetRecognitionWorker(stance: stance)
        let adapter = MoveNetFrameAdapter(process: { frame in relay.deliver(try worker.process(frame)) }, failed: { relay.fail($0) })
        self.adapter = adapter; engine = CaptureEngine(frameAdapter: adapter)
        relay.set(sample: { [weak self] sample in Task { @MainActor in self?.receive(sample) } }, failure: { [weak self] _ in
            Task { @MainActor in self?.error = "Recognition could not process this frame. Reopen the camera test to retry." }
        })
    }
    private func receive(_ observation: MoveNetRecognitionWorker.Observation) {
        guard active, adapter.isCurrent(generation: observation.generation) else { return }
        if generation != observation.generation {
            generation = observation.generation; seen.removeAll(); observed = "No straight punch observed"
        }
        seen = seen.filter { $0.value >= observation.captureMs - 5000 }
        received += 1; latencyMs = observation.finishedMs - observation.captureMs
        if !observation.timingReliable { tracking = "Timing uncertain" }
        else if observation.sample.frame.lost { tracking = "Step into clear view" }
        else {
            switch observation.sample.status {
            case "ok": tracking = "Tracking ready"
            case "hold_still": tracking = "Hold your stance to calibrate"
            case "too_far": tracking = "Move a little closer"
            case "too_close": tracking = "Move a little farther back"
            default: tracking = "Keep shoulders and hands visible"
            }
        }
        for event in observation.sample.punches where event.rejected == nil && event.candidate.kind == .straight {
            let c = event.candidate
            let id = c.actionId ?? "\(c.limb.rawValue):\(c.tOnsetMs)"
            guard seen[id] == nil else { continue }; seen[id] = c.tPeakMs
            let lead: BoxMaxxingJudge.Limb = stance == .orthodox ? .left : .right
            observed = c.limb == lead ? "Jab observed · unvalidated" : "Cross observed · unvalidated"
        }
    }
    func start() async {
        error = nil; active = true
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted, !Task.isCancelled, active else {
            if !granted { tracking = "Camera access needed"; error = "Allow camera access in Settings to test recognition." }
            return
        }
        do {
            try await engine.start()
            if Task.isCancelled || !active { engine.stop() } else { ready = true }
        } catch { tracking = "Camera unavailable"; self.error = error.localizedDescription }
    }
    func stop() { active = false; ready = false; tracking = "Camera paused"; engine.stop() }
    func record(label: ValidationLabel, store: AppStore) {
        guard ready, !recording, !saving else { return }
        notice = nil; error = nil; recording = true
        let stance = stance.rawValue
        engine.record { [weak self] url, failure in
            Task { @MainActor in
                guard let self else { return }
                defer { self.recording = false; self.saving = false }
                if let url {
                    defer { try? FileManager.default.removeItem(at: url) }
                    if await store.saveVideo(from: url, title: "\(label.rawValue) · Camera test", kind: "Validation · \(label.rawValue) · \(stance)") {
                        self.notice = "Test clip saved to Review. Its label is your description, not verified ground truth."
                    } else { self.error = store.storageNotice }
                } else { self.error = failure ?? "The test clip could not be saved." }
            }
        }
    }
    func finish() { guard recording else { return }; saving = true; engine.stopRecording() }
}

private enum ValidationLabel: String, CaseIterable, Identifiable, Sendable {
    case jab = "Jab", cross = "Cross", idle = "Idle", other = "Other movement", visibility = "Poor visibility"
    var id: Self { self }
    var instruction: String {
        switch self {
        case .jab: "Record 10 separate jabs, returning to guard between punches."
        case .cross: "Record 10 separate crosses, returning to guard between punches."
        case .idle: "Record 10 seconds in stance without punching."
        case .other: "Record natural movement without throwing punches."
        case .visibility: "Record a short clip with hands partly out of view."
        }
    }
}

/// Development validation tool. It does not launch a competing session player,
/// award performance credit, or expose an unavailable planning capability.
struct CameraValidationView: View {
    let store: AppStore
    @State private var camera: CameraValidationController
    @State private var label: ValidationLabel = .jab
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase

    init(store: AppStore) {
        self.store = store
        let stance: BoxMaxxingJudge.Stance = store.stance.lowercased().contains("south") ? .southpaw : .orthodox
        _camera = State(initialValue: CameraValidationController(stance: stance))
    }
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.engine.session).ignoresSafeArea().accessibilityLabel("Live front camera preview")
            LinearGradient(colors: [.black.opacity(0.75), .clear, .black.opacity(0.95)], startPoint: .top, endPoint: .bottom).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Camera test").boxDisplay(30, relativeTo: .title2)
                        Text("\(camera.stance.rawValue.capitalized) · Unscored").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer()
                    GlassIconButton(symbol: "xmark", label: "Close camera test") { dismiss() }.disabled(camera.recording)
                }
                Text(camera.tracking).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.black.opacity(0.6), in: .capsule).overlay { Capsule().strokeBorder(.white.opacity(0.12)) }
                Spacer(minLength: 24)
                VStack(alignment: .leading, spacing: 12) {
                    BoxFeatureLabel(title: "Recognition under validation", symbol: "viewfinder", color: BoxStyle.timer)
                    Text(camera.observed).boxSection(24)
                    if let latency = camera.latencyMs {
                        Text("\(Int(latency)) ms capture to result · \(camera.received) processed frames").font(.caption.monospacedDigit()).foregroundStyle(BoxStyle.muted)
                    }
                    Picker("Test clip label", selection: $label) {
                        ForEach(ValidationLabel.allCases) { Text($0.rawValue).tag($0) }
                    }.tint(.white).frame(minHeight: 44).disabled(camera.recording)
                    Text(label.instruction).font(.subheadline).foregroundStyle(BoxStyle.muted)
                    if camera.recording {
                        PrimaryButton(title: camera.saving ? "Saving…" : "Stop & save", symbol: "stop.fill") { camera.finish() }.disabled(camera.saving)
                    } else {
                        PrimaryButton(title: "Record test clip", symbol: "record.circle") { camera.record(label: label, store: store) }.disabled(!camera.ready)
                    }
                    if let notice = camera.notice { Text(notice).font(.footnote) }
                    if let error = camera.error { Text(error).font(.footnote).foregroundStyle(BoxStyle.accent) }
                    Text("Detections are not verified technique or training scores. Nothing is recorded until you tap Record.")
                        .font(.caption).foregroundStyle(BoxStyle.muted)
                }.padding(18)
                    .background(BoxStyle.surface.opacity(0.96), in: .rect(cornerRadius: 26, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(BoxStyle.border) }
            }.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .foregroundStyle(.white).preferredColorScheme(.dark)
        .interactiveDismissDisabled(camera.recording)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .onChange(of: phase) { _, next in
            if next != .active { camera.stop() }
            else { Task { await camera.start() } }
        }
    }
}
