import AVFoundation
import Observation
import OSLog
import SwiftUI

@MainActor @Observable
final class PadTrainingCamera {
    struct Response { let id: UUID; let outcome: String; let reactionMs: Double?; let targetMatch: PadTargetMatch? }
    enum Event {
        case response(Response)
        case interrupted(UUID, String)
        case unjudged(UUID, String)
    }
    enum Readiness: Equatable {
        case inView, unclear, adjust, delayed, paused, unavailable
        var label: LocalizedStringResource {
            switch self {
            case .inView: "You’re in view"
            case .unclear: "Tracking unclear"
            case .adjust: "Adjust your position"
            case .delayed: "Camera delayed"
            case .paused: "Camera paused"
            case .unavailable: "Camera unavailable"
            }
        }
    }
    @ObservationIgnored let engine: CaptureEngine
    @ObservationIgnored private let worker: MoveNetRecognitionWorker
    @ObservationIgnored private let adapter: MoveNetFrameAdapter
    @ObservationIgnored private let relay: PadFrameRelay
    @ObservationIgnored private let stance: BoxMaxxingJudge.Stance
    @ObservationIgnored private let log = Logger(subsystem: "com.boxing.prototype", category: "PadTracking")
    @ObservationIgnored private let configuration: PadConfiguration
    @ObservationIgnored private var reach: PadReachCalibration
    @ObservationIgnored private var latestBody: PadBodyFrame?
    @ObservationIgnored private let probeID = UUID()
    @ObservationIgnored private var samplingReach = true
    @ObservationIgnored private var viewportSize = CGSize.zero
    @ObservationIgnored private var lastCaptureMs = -Double.infinity
    @ObservationIgnored private var lastSequence: UInt64?
    @ObservationIgnored private var lastUIUpdate = -Double.infinity
    @ObservationIgnored private var activeCue: UUID?
    @ObservationIgnored private var events: [Event] = []
    @ObservationIgnored private var diagnostics = PadCameraDiagnostics()
    @ObservationIgnored private var lastIssue: String?
    @ObservationIgnored private var lifecycle = UUID()
    @ObservationIgnored private var sessionPaused = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private(set) var started = false
    private(set) var error: String?
    private(set) var readiness: Readiness = .paused
    private(set) var tracking = "Keep your shoulders, elbows and hands in view, with room to extend both arms."
    private(set) var generation: UInt64?
    private(set) var trackingReason = "camera_starting"
    private(set) var trackingReady = false
    private(set) var canPresentCue = false
    private(set) var scoringReady = false
    private(set) var calibrationText = "Hold your guard briefly to calibrate."
    private(set) var processingText: String?
    private(set) var recognitionText: String?
    private(set) var imageSize = CGSize(width: 720, height: 1280)
    private(set) var rotationDegrees = 90
    private(set) var target: PadTargetDefinition?
    private(set) var lastTargetMatch: PadTargetMatch?
    private(set) var reachStage: PadReachCalibration.Stage = .idle
    private(set) var reachInstruction = "Calibrate comfortable reach before target-accuracy practice."
    private(set) var targetNotice: String?
    var showAlignment = false
    private(set) var alignmentPoints: [PadPoint?] = []
    private(set) var alignmentAgeMs = 0
    var needsReach: Bool { configuration.effectiveTargetMode == .accuracy }
    var reachReady: Bool { !needsReach || reachStage == .ready }

    init(configuration: PadConfiguration, diagnostics: PadCameraDiagnostics = .init()) {
        let stance = configuration.stance
        self.stance = stance
        self.configuration = configuration
        let hands: [BoxMaxxingJudge.Hand] = configuration.activityID == "jab-reset-v1" ? [.lead] : configuration.activityID == "cross-reset-v1" ? [.rear] : [.lead, .rear]
        reach = PadReachCalibration(stance: stance, hands: hands)
        self.diagnostics = diagnostics
        let relay = PadFrameRelay()
        self.relay = relay
        let worker = MoveNetRecognitionWorker(stance: stance, upperBodyOnly: true)
        self.worker = worker
        adapter = MoveNetFrameAdapter(process: { relay.deliver(try worker.process($0)) }, failed: { relay.fail($0) })
        engine = CaptureEngine(frameAdapter: adapter)
        // The timer also drains this mailbox before freshness checks. A queued
        // completed judgment must win over a later UI freshness timeout.
        relay.changed = { [weak self] in
            let camera = self
            DispatchQueue.main.async { camera?.receivePending() }
        }
    }
    func startReachCalibration() {
        guard activeCue == nil else { return }
        reach.start(at: ProcessInfo.processInfo.systemUptime * 1000)
        target = nil; canPresentCue = false; updateReachText()
    }
    private func updateReachText() {
        reachStage = reach.stage; reachInstruction = reach.instruction
    }
    func setReachSampling(_ value: Bool) {
        if samplingReach && !value { reach.discardRecentPose() }
        samplingReach = value
    }
    func setViewport(_ size: CGSize) { viewportSize = size }
    @discardableResult func prepare(id: UUID, hand: BoxMaxxingJudge.Hand) -> Bool {
        guard needsReach else { target = nil; return true }
        if target?.cueID == id { return true }
        guard let generation, let next = reach.target(id: id, hand: hand, generation: generation, level: configuration.level), next.fitsSource else { return false }
        target = next; lastTargetMatch = nil
        return true
    }
    func start() async {
        guard !started else { return }
        let token = UUID(); lifecycle = token
        error = nil; sessionPaused = false; readiness = .unclear; trackingReason = "camera_starting"
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            guard lifecycle == token, !Task.isCancelled else { return }
            error = "Allow camera access in Settings to practise with camera."; readiness = .unavailable; return
        }
        guard lifecycle == token, !Task.isCancelled else { return }
        do {
            try await engine.start()
            guard lifecycle == token, !Task.isCancelled else {
                if lifecycle == token { engine.stop() }
                return
            }
            started = true
            observeSession(token: token)
        } catch {
            guard lifecycle == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription; readiness = .unavailable
        }
    }
    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        lifecycle = UUID(); suspend(); engine.stop(); started = false
        lastCaptureMs = -.infinity; generation = nil; lastSequence = nil
        reach.reset(); updateReachText(); target = nil; lastTargetMatch = nil; latestBody = nil; alignmentPoints = []
        trackingReady = false; canPresentCue = false; scoringReady = false
        readiness = .paused
        _ = relay.drain(); events.removeAll()
    }
    private func observeSession(token: UUID) {
        for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.interruptionEndedNotification, AVCaptureSession.runtimeErrorNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: engine.session, queue: .main) { [weak self] notification in
                let message = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                Task { @MainActor in
                    guard let self, self.lifecycle == token, self.started else { return }
                    if name == AVCaptureSession.runtimeErrorNotification {
                        self.error = message ?? "Camera stopped. Pause and resume to retry."
                        self.loseTracking(reason: "camera_error"); self.readiness = .unavailable
                    } else if name == AVCaptureSession.wasInterruptedNotification {
                        self.sessionPaused = true; self.loseTracking(reason: "camera_interrupted")
                        self.readiness = .paused; self.tracking = "The camera was interrupted. Wait for it to resume, or pause and retry."
                    } else {
                        self.sessionPaused = false; self.loseTracking(reason: "camera_restarting")
                    }
                }
            }
            observers.append(observer)
        }
    }
    func suspend() { activeCue = nil; worker.setPresentedCue(nil) }
    func drainEvents() -> [Event] { defer { events.removeAll() }; return events }
    func diagnosticsSnapshot() -> PadCameraDiagnostics { diagnostics }
    @discardableResult func present(id: UUID, hand: BoxMaxxingJudge.Hand, level: PadLevel, atMs: Double) -> Bool {
        guard canPresentCue, ProcessInfo.processInfo.systemUptime * 1000 - lastCaptureMs < 400, let generation else { return false }
        if needsReach {
            guard let target, target.cueID == id, target.generation == generation, target.hand == hand,
                  let latestBody, target.body.compatible(with: latestBody),
                  (latestBody.centre - target.body.centre).length < target.body.scale * 0.3 else {
                events.append(.interrupted(id, "target_alignment_changed")); return false
            }
        }
        activeCue = id
        reach.discardRecentPose()
        log.info("cue_presented id=\(id.uuidString, privacy: .public) generation=\(generation)")
        worker.setPresentedCue(.init(id: id, hand: hand, generation: generation, visibleMs: atMs, responseSeconds: level.responseSeconds, target: needsReach ? target : nil))
        return true
    }
    /// Short gaps stop scoring/new cues immediately, but keep the active cue.
    /// Only a sustained delivery gap cancels it. Never expire from last *good*
    /// pose: a sequence of fresh, briefly uncertain frames is not a stalled camera.
    func refreshFreshness() {
        receivePending()
        guard started, !sessionPaused, error == nil else { return }
        let age = ProcessInfo.processInfo.systemUptime * 1000 - lastCaptureMs
        if age >= 400 {
            scoringReady = false; canPresentCue = false
            readiness = .delayed; processingText = "Camera processing is delayed—pause and retry."
            if age >= 800 { loseTracking(reason: "ui_delivery_stale") }
        }
    }
    private func receivePending() {
        for delivery in relay.drain() {
            switch delivery {
            case .sample(let observation): receive(observation)
            case .failure(let detail):
                guard started else { continue }
                error = "Camera tracking stopped. Pause and resume to retry."
                loseTracking(reason: "worker_error"); readiness = .unavailable
                log.error("worker_error: \(detail, privacy: .public)")
            }
        }
    }
    private func loseTracking(reason: String) {
        if lastIssue != reason { log.info("cueing_paused reason=\(reason, privacy: .public) cue=\(self.activeCue?.uuidString ?? "none", privacy: .public)") }
        lastIssue = reason; trackingReason = reason
        setTrackingReady(false, reason: reason); canPresentCue = false; scoringReady = false
        if let activeCue { events.append(.interrupted(activeCue, reason)); suspend() }
        if PadTrackingGuidance.isProcessing(reason) {
            readiness = .delayed; processingText = PadTrackingGuidance.instruction(reason)
        } else {
            readiness = reason == "calibration_too_far" || reason == "calibration_too_close" ? .adjust : .unclear
            tracking = PadTrackingGuidance.instruction(reason)
        }
    }
    private func setTrackingReady(_ value: Bool, reason: String) {
        if trackingReady && !value {
            diagnostics.interruptionEpisodes = (diagnostics.interruptionEpisodes ?? 0) + 1
            if diagnostics.interruptionCauses == nil { diagnostics.interruptionCauses = [:] }
            diagnostics.interruptionCauses?[reason, default: 0] += 1
            log.info("interruption_episode reason=\(reason, privacy: .public) cue=\(self.activeCue?.uuidString ?? "none", privacy: .public)")
        }
        trackingReady = value
    }
    private func receive(_ observation: MoveNetRecognitionWorker.Observation) {
        guard started else { return }
        let now = ProcessInfo.processInfo.systemUptime * 1000
        let age = now - observation.captureMs
        // A completed judgment is immutable and belongs to its original cue.
        // Consume before a later loss/stale delivery, even if UI was delayed.
        if let cue = observation.judgedCueID, cue == activeCue, observation.generation == generation {
            if let reason = observation.cueUnjudged {
                events.append(.unjudged(cue, reason)); suspend()
                log.info("response_uncertain cue=\(cue.uuidString, privacy: .public) reason=\(reason, privacy: .public)")
            } else if let reason = observation.cueInterruption {
                events.append(.interrupted(cue, reason)); suspend()
            }
            for event in observation.responseEvents {
                let outcome: String
                switch event.kind {
                case "rep_ok": outcome = event.grade == "yellow" ? "hit_yellow" : "hit_green"
                case "rep_wrong_hand": outcome = "wrong_hand"
                case "rep_wrong_kind": outcome = "wrong_kind"
                case "rep_timeout": outcome = event.reason == "early" ? "early" : "miss_timeout"
                default: continue
                }
                events.append(.response(.init(id: cue, outcome: outcome, reactionMs: event.reactionMs, targetMatch: observation.targetMatch)))
                if let match = observation.targetMatch {
                    lastTargetMatch = match
                    log.info("target_result cue=\(cue.uuidString, privacy: .public) result=\(match.outcome.rawValue, privacy: .public) reason=\(match.reason ?? "none", privacy: .public) calibration=\(match.target.calibrationID.uuidString, privacy: .public)")
                }
                log.info("response id=\(cue.uuidString, privacy: .public) outcome=\(outcome, privacy: .public) ageMs=\(age) processingMs=\(observation.processingMs) deliveryMs=\(now - observation.finishedMs)")
                suspend(); break
            }
        }
        // A source change invalidates pose/readiness, but must not erase a
        // completed result already queued for the still-active original cue.
        guard !sessionPaused, error == nil, adapter.isCurrent(generation: observation.generation) else { return }
        if generation != observation.generation {
            if generation != nil { diagnostics.generationChanges += 1; loseTracking(reason: "source_generation") }
            generation = observation.generation; lastSequence = nil
            reach.reset("Camera orientation or source changed. Recalibrate reach."); target = nil; updateReachText()
        }
        guard lastSequence.map({ observation.sequence > $0 }) ?? true else { diagnostics.rejectedDeliveries += 1; return }
        lastSequence = observation.sequence
        diagnostics.frames += 1
        diagnostics.maxCaptureAgeMs = max(diagnostics.maxCaptureAgeMs, age)
        diagnostics.maxProcessingMs = max(diagnostics.maxProcessingMs, observation.processingMs)
        diagnostics.maxDeliveryMs = max(diagnostics.maxDeliveryMs, now - observation.finishedMs)

        lastCaptureMs = observation.captureMs
        let size = CGSize(width: observation.width, height: observation.height)
        if imageSize != size { imageSize = size }
        if rotationDegrees != observation.rotationDegrees { rotationDegrees = observation.rotationDegrees }
        let status = observation.tracking
        var issue = observation.trackingIssue
        if age < 0 || age >= 400 { issue = "ui_delivery_stale" }
        if let issue {
            diagnostics.frameIssues[issue, default: 0] += 1
            if lastIssue != issue {
                let scores = [5, 6, 7, 8, 9, 10].map { "\($0):" + String(format: "%.2f", observation.pose[$0].score) }.joined(separator: ",")
                log.info("frame_issue reason=\(issue, privacy: .public) generation=\(observation.generation) sequence=\(observation.sequence) status=\(observation.sample.status, privacy: .public) lost=\(observation.sample.frame.lost) bodyVisible=\(status.bodyInView) canScore=\(status.canScore) legacyFraming=\(observation.sample.presence?.framing ?? "missing", privacy: .public) ageMs=\(age) processingMs=\(observation.processingMs) deliveryMs=\(now - observation.finishedMs)")
                log.info("upper_point_scores=\(scores, privacy: .public) crop=full_source")
            }
        }
        if status.bodyInView && observation.sample.presence?.supportsUpperBody != true {
            diagnostics.legacyPresenceDisagreements = (diagnostics.legacyPresenceDisagreements ?? 0) + 1
        }
        let fresh = age >= 0 && age < 400
        setTrackingReady(status.canContinue && age < 800,
                         reason: age >= 800 ? "ui_delivery_stale" : status.interruptionReason ?? "tracking_recovering")
        canPresentCue = status.canStartCue && fresh
        scoringReady = status.canScore && fresh
        let points: [PadPoint?] = observation.pose.map {
            $0.score >= 0.3 && (0...1).contains($0.x) && (0...1).contains($0.y) ? .init(x: $0.x, y: $0.y) : nil
        }
        latestBody = scoringReady ? PadBodyFrame(points: points, aspect: Double(observation.width) / Double(observation.height)) : nil
        if needsReach && activeCue == nil && samplingReach {
            if scoringReady { reach.observe(.init(tMs: observation.captureMs, points: points, aspect: Double(observation.width) / Double(observation.height))) }
            else { reach.discardRecentPose() }
            updateReachText()
            let targets = reach.hands.compactMap { reach.target(id: probeID, hand: $0, generation: observation.generation, level: configuration.level) }
            let guardReady = targets.count == reach.hands.count
            let fit = guardReady && targets.allSatisfy(\.fitsSource)
            let mapping = PadCameraTransform(image: imageSize, viewport: viewportSize)
            let minimumDiameter = configuration.level == .beginner ? 24.0 : configuration.level == .intermediate ? 20.0 : 16.0
            let readable = fit && targets.allSatisfy { mapping.region($0).width >= minimumDiameter }
            canPresentCue = canPresentCue && readable
            if guardReady && !fit {
                targetNotice = "Your calibrated reach falls outside the camera view. Reframe with room around both arms, then recalibrate. Targets are never moved to fit."
            } else if fit && !readable && viewportSize != .zero {
                targetNotice = "Projected reach is too small to aim reliably in this view. Reframe to show a larger upper body or use a slight camera angle, then recalibrate."
            } else {
                targetNotice = reach.stage == .ready && !guardReady ? "Return to your calibrated guard briefly before the next cue." : nil
            }
        }
        scoringReady = scoringReady && reachReady
        trackingReason = status.interruptionReason ?? issue ?? "tracking_recovering"
        calibrationText = status.calibration == "ok" ? "Calibrated for jab/cross · upper body" :
            PadTrackingGuidance.instruction("calibration_" + status.calibration)
        processingText = !fresh ? PadTrackingGuidance.instruction("ui_delivery_stale") :
            status.processingIssue.map(PadTrackingGuidance.instruction)
        recognitionText = fresh && status.bodyInView && status.calibration == "ok" && !status.canScore ?
            (activeCue != nil ? "Checking the response. Brief uncertainty is not a missed punch." :
                "Brief arm uncertainty. Waiting for clear points before the next cue.") : nil
        if processingText != nil { readiness = .delayed }
        else if status.calibration == "too_far" || status.calibration == "too_close" { readiness = .adjust }
        else { readiness = status.bodyInView ? .inView : .unclear }
        tracking = status.bodyInView ? "Keep room to extend both arms. Your hips and legs do not need to be visible." :
            "Keep both shoulders and arms in view."
        if status.calibration != "ok" { tracking = calibrationText }
        if lastIssue != issue && issue == nil && status.canStartCue {
            log.info("tracking_recovered generation=\(observation.generation) sequence=\(observation.sequence) ageMs=\(age)")
        }
        lastIssue = issue
        if showAlignment || now - lastUIUpdate > 250 {
            lastUIUpdate = now
            alignmentPoints = showAlignment && fresh ? points : []
            alignmentAgeMs = Int(max(0, age))
        }
    }
}

/// Closures are installed once before capture starts; all deliveries preserve FIFO order.
private final class PadFrameRelay: @unchecked Sendable {
    enum Delivery { case sample(MoveNetRecognitionWorker.Observation), failure(String) }
    var changed: (@Sendable () -> Void)?
    private let lock = NSLock()
    private var pending: [Delivery] = []
    func deliver(_ value: MoveNetRecognitionWorker.Observation) { append(.sample(value)) }
    func fail(_ detail: String) { append(.failure(detail)) }
    private func append(_ delivery: Delivery) {
        lock.lock(); pending.append(delivery); lock.unlock()
        changed?()
    }
    func drain() -> [Delivery] {
        lock.lock(); defer { lock.unlock() }
        let deliveries = pending; pending.removeAll(keepingCapacity: true); return deliveries
    }
}

/// Shares the result card's layout pass and acknowledges a subsequent display
/// link. Like cue acknowledgement, this is not a measured photon timestamp.
struct PadOutcomeAcknowledgement: UIViewRepresentable {
    let id: UUID
    let presented: (UUID, Double) -> Void
    func makeUIView(context: Context) -> PadOutcomeSurface { PadOutcomeSurface() }
    func updateUIView(_ view: PadOutcomeSurface, context: Context) { view.configure(id: id, presented: presented) }
}

final class PadOutcomeSurface: UIView {
    private var id: UUID?
    private var submittedID: UUID?
    private var link: CADisplayLink?
    private var presented: ((UUID, Double) -> Void)?
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(id: UUID, presented: @escaping (UUID, Double) -> Void) {
        self.presented = presented
        guard self.id != id else { return }
        link?.invalidate(); link = nil; self.id = id; submittedID = nil; setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard submittedID != id, link == nil else { return }
        link = CADisplayLink(target: self, selector: #selector(submitted))
        link?.add(to: .main, forMode: .common)
    }
    @objc private func submitted() {
        guard window != nil, !isHidden, alpha > 0, let id else { return }
        link?.invalidate(); link = nil
        guard submittedID != id else { return }; submittedID = id
        presented?(id, ProcessInfo.processInfo.systemUptime)
    }
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { link?.invalidate(); link = nil } else { setNeedsDisplay() }
    }
}

/// Draw first, then acknowledge a subsequent display-link callback. This is a
/// renderer submission boundary, not a measured hardware photon timestamp.
struct PadTargetCanvas: UIViewRepresentable {
    let cueID: UUID
    let level: PadLevel
    let target: PadTargetDefinition?
    let imageSize: CGSize
    let handTitle: String
    let presented: (UUID, Double) -> Bool
    func makeUIView(context: Context) -> PadTargetSurface { PadTargetSurface() }
    func updateUIView(_ view: PadTargetSurface, context: Context) {
        view.configure(cueID: cueID, level: level, target: target, image: imageSize, title: handTitle, presented: presented)
    }
}

final class PadTargetSurface: UIView {
    private var cueID: UUID?
    private var drawnID: UUID?
    private var ackID: UUID?
    private var link: CADisplayLink?
    private var level: PadLevel = .beginner
    private var target: PadTargetDefinition?
    private var image = CGSize(width: 1, height: 1)
    private var title = ""
    private var presented: ((UUID, Double) -> Bool)?
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false; isUserInteractionEnabled = false }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func configure(cueID: UUID, level: PadLevel, target: PadTargetDefinition?, image: CGSize, title: String, presented: @escaping (UUID, Double) -> Bool) {
        self.presented = presented
        guard self.cueID != cueID else { return } // Freeze the guide for this attempt; never chase frame jitter.
        link?.invalidate(); link = nil; drawnID = nil
        self.cueID = cueID; self.level = level; self.target = target; self.image = image; self.title = title
        setNeedsDisplay()
    }
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), let cueID else { return }
        let mapping = PadCameraTransform(image: image, viewport: bounds.size)
        let centre = target.map { mapping.screen($0.centre) } ?? CGPoint(x: bounds.midX, y: bounds.midY)
        if let target {
            let region = mapping.region(target)
            let start = mapping.screen(target.origin)
            if level == .beginner {
                ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.75).cgColor); ctx.setLineWidth(3); ctx.setLineDash(phase: 0, lengths: [6, 6])
                ctx.move(to: start); ctx.addLine(to: centre); ctx.strokePath(); ctx.setLineDash(phase: 0, lengths: [])
                ctx.setFillColor(UIColor.white.withAlphaComponent(0.8).cgColor); ctx.fillEllipse(in: CGRect(x: start.x - 8, y: start.y - 8, width: 16, height: 16))
            }
            ctx.setFillColor(UIColor.black.withAlphaComponent(0.4).cgColor)
            ctx.fillEllipse(in: region)
            ctx.setStrokeColor(UIColor.systemGreen.cgColor); ctx.setLineWidth(4)
            ctx.strokeEllipse(in: region)
        }
        // The result/cue card names the punch. Keep the accuracy region clear
        // so its full visible boundary, and the wrist within it, remain readable.
        let text = (target == nil ? title + " · REACTION" : "") as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 18, weight: .bold), .foregroundColor: UIColor.white]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: centre.x - size.width / 2, y: centre.y - size.height / 2), withAttributes: attributes)
        drawnID = cueID
        if ackID != cueID && link == nil {
            let link = CADisplayLink(target: self, selector: #selector(frameSubmitted))
            self.link = link; link.add(to: .main, forMode: .common)
        }
    }
    @objc private func frameSubmitted() {
        guard window != nil, !isHidden, alpha > 0, let id = drawnID, id == cueID else { return }
        guard ackID != id else { link?.invalidate(); link = nil; return }
        // If this draw coincided with a brief scoring gap, retry the renderer
        // acknowledgement on the next display link; do not strand this cue.
        if presented?(id, ProcessInfo.processInfo.systemUptime * 1000) == true {
            ackID = id; link?.invalidate(); link = nil
        }
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { link?.invalidate(); link = nil } else { setNeedsDisplay() } }
}
