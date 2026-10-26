import Foundation
import Observation
import OSLog
import SwiftUI

/// Runs one sparring session: camera → pose → (kernel + native recogniser →
/// fusion) → engine. Everything is on the capture clock (ms of system uptime).
@MainActor @Observable
final class SparringSession {
    enum Stage: Equatable { case framing, countdown(Int), fighting, paused, finished }

    struct Effect: Identifiable, Equatable {
        let id = UUID()
        let result: SparringResult
        let anchor: CGPoint
        let startMs: Double
    }

    let configuration: SparringConfiguration
    let camera: PadTrainingCamera
    private(set) var engine: SparringEngine
    private(set) var stage: Stage = .framing
    private(set) var effects: [Effect] = []
    private(set) var lastResult: SparringResult?
    private(set) var resultID = 0
    /// Smoothed body frame used to lay targets out around the fighter.
    private(set) var body: PadBodyFrame?
    private(set) var imageSize = CGSize(width: 720, height: 1280)
    private(set) var viewport = CGSize.zero
    private(set) var feedback: String?
    private(set) var feedbackID = 0
    private(set) var lastDetected: FightAction?
    private(set) var detectedID = 0

    @ObservationIgnored private var recognizer = MoveRecognizer()
    @ObservationIgnored private var fusion = MoveFusion()
    @ObservationIgnored private var readySince: Double?
    @ObservationIgnored private var countdownStart: Double?
    @ObservationIgnored private let log = Logger(subsystem: "com.boxing.prototype", category: "Sparring")

    init(configuration: SparringConfiguration) {
        self.configuration = configuration
        engine = SparringEngine(configuration: configuration)
        var pad = PadConfiguration(mode: .rounds, level: .advanced, stance: configuration.stance)
        pad.targetMode = .reaction
        camera = PadTrainingCamera(configuration: pad)
        camera.onFrame = { [weak self] observation in self?.receive(observation) }
    }

    static var now: Double { ProcessInfo.processInfo.systemUptime * 1000 }
    var isFighting: Bool { stage == .fighting }

    func setViewport(_ size: CGSize) { viewport = size; camera.setViewport(size) }

    // MARK: Clock

    /// Called ~60×/s by the arena.
    func tick() {
        let now = Self.now
        camera.refreshFreshness()
        effects.removeAll { now - $0.startMs > 900 }
        switch stage {
        case .framing, .countdown:
            advanceCountdown(now: now)
        case .fighting:
            for event in engine.update(atMs: now) { handle(event) }
            #if DEBUG
            if debugAutoplay {
                for beat in engine.active where now >= beat.hitMs - 40 {
                    // Mostly on-beat with an occasional wrong move, to show every effect.
                    let action = beat.id % 9 == 4 ? FightAction.straight(beat.action.side == .left ? .right : .left) : beat.action
                    for event in engine.receive(.init(action: action, startMs: now - 200, peakMs: now, confidence: 1, source: .native)) { handle(event) }
                }
            }
            #endif
        case .paused, .finished:
            break
        }
    }

    private func advanceCountdown(now: Double) {
        guard camera.trackingReady, camera.error == nil else {
            readySince = nil
            if case .countdown = stage, now - (countdownStart ?? now) > 400 { stage = .framing; countdownStart = nil }
            return
        }
        if readySince == nil { readySince = now }
        if countdownStart == nil, now - (readySince ?? now) >= 600 { countdownStart = now }
        guard let start = countdownStart else { return }
        let remaining = 3 - Int((now - start) / 1000)
        if remaining <= 0 {
            stage = .fighting; countdownStart = nil
            if engine.phase == .ready { engine.start(atMs: now) }
            BoxHaptics.heavy()
        } else if stage != .countdown(remaining) {
            stage = .countdown(remaining); BoxHaptics.impact()
        }
    }

    // MARK: Frames

    private func receive(_ observation: MoveNetRecognitionWorker.Observation) {
        let aspect = Double(observation.width) / Double(observation.height)
        imageSize = CGSize(width: observation.width, height: observation.height)
        let points: [PadPoint?] = observation.pose.map {
            $0.score >= 0.25 && (-0.1...1.1).contains($0.x) && (-0.1...1.1).contains($0.y) ? PadPoint(x: $0.x, y: $0.y) : nil
        }
        if let frame = PadBodyFrame(points: points, aspect: aspect) {
            if let body, body.compatible(with: frame, scaleTolerance: 0.5) {
                // Low-pass the layout frame so targets do not jitter with the pose.
                let centre = body.centre * 0.85 + frame.centre * 0.15
                let scale = body.scale * 0.85 + frame.scale * 0.15
                self.body = PadBodyFrame(centre: centre, scale: scale, like: frame)
            } else { body = frame }
        }
        let native = recognizer.push(.init(tMs: observation.captureMs, points: points, aspect: aspect))
        let current = recognizer
        let moves = fusion.push(native: native, kernel: observation.sample.punches, nowMs: observation.captureMs,
                                busy: { current.specificInProgress(side: $0) })
        for move in moves {
            log.info("move=\(move.action.kind.rawValue, privacy: .public) side=\(move.action.side.rawValue, privacy: .public) source=\(move.source.rawValue, privacy: .public) conf=\(move.confidence)")
            lastDetected = move.action; detectedID += 1
            guard stage == .fighting else { continue }
            for event in engine.receive(move) { handle(event) }
        }
    }

    // MARK: Events

    private func handle(_ event: SparringEngine.Event) {
        switch event {
        case .resolved(let result):
            lastResult = result; resultID += 1
            effects.append(.init(result: result, anchor: screenPoint(for: result.beat.action), startMs: Self.now))
            if result.grade.isHit {
                result.grade == .perfect ? BoxHaptics.heavy() : BoxHaptics.impact()
                if engine.streak > 0 && engine.streak % 10 == 0 { BoxHaptics.success() }
            } else {
                BoxHaptics.warning()
                if result.grade == .wrong, let detected = result.detected {
                    say(String(localized: "That was a \(detected.title(stance: configuration.stance).lowercased()). Throw the \(result.beat.action.title(stance: configuration.stance).lowercased())."))
                } else if result.beat.action.kind == .slip || result.beat.action.kind == .duck {
                    say(result.beat.action.kind == .duck ? String(localized: "Get lower, faster.") : String(localized: "Move your head off the line, faster."))
                }
            }
        case .knockedOut:
            BoxHaptics.heavy(); stage = .finished
        case .finished:
            stage = .finished
        case .roundStarted, .roundEnded, .spawned:
            break
        }
    }

    private func say(_ text: String) { feedback = text; feedbackID += 1 }

    // MARK: Controls

    func start() async {
        #if DEBUG
        if debugAutoplay { stage = .fighting; engine.start(atMs: Self.now); return }
        #endif
        await camera.start()
    }
    #if DEBUG
    /// Design QA: no camera, perfect-ish simulated fighter.
    @ObservationIgnored var debugAutoplay = false
    #endif
    func stop() { camera.stop() }
    func pause() { guard stage != .finished else { return }; stage = .paused; camera.suspend() }
    func resume() { guard stage == .paused else { return }; stage = engine.phase == .ready ? .framing : .fighting }
    func end() { stage = .finished }

    func record() -> SessionRecord {
        let summary = engine.summary
        var record = SessionRecord(id: UUID(), date: .now, focus: .mixed, activeSeconds: summary.activeSeconds, workSeconds: summary.activeSeconds,
                                   completedRounds: summary.roundsCompleted, skippedBlocks: 0, issuedCues: summary.attempts,
                                   finished: !summary.knockedOut && engine.phase == .finished)
        record.sparring = summary
        return record
    }

    // MARK: Layout

    /// Where a target for this move sits, in the fighter's body frame
    /// (x toward the fighter's right, y down, shoulder widths).
    static func layout(for action: FightAction) -> PadPoint {
        let sign: Double = action.side == .left ? -1 : 1
        switch action.kind {
        case .straight: return .init(x: sign * 0.45, y: -0.75)
        case .hook: return .init(x: sign * 1.35, y: -0.6)
        case .uppercut: return .init(x: sign * 0.4, y: 0.35)
        case .slip: return .init(x: sign * -0.2, y: -1.15)
        case .duck: return .init(x: 0, y: -1.25)
        }
    }

    /// Screen position (mirrored preview) for a move's target.
    func screenPoint(for action: FightAction, local override: PadPoint? = nil) -> CGPoint {
        let mapping = PadCameraTransform(image: imageSize, viewport: viewport)
        guard let body, viewport != .zero else {
            let fallback = Self.layout(for: action)
            return CGPoint(x: viewport.width / 2 - fallback.x * viewport.width * 0.18, y: viewport.height * 0.42 + fallback.y * viewport.width * 0.18)
        }
        return mapping.screen(body.source(override ?? Self.layout(for: action)))
    }
    /// Shoulder width in points, for sizing targets.
    var screenScale: CGFloat {
        guard let body, viewport != .zero else { return viewport.width * 0.22 }
        let mapping = PadCameraTransform(image: imageSize, viewport: viewport)
        return mapping.imageRect.height * body.scale
    }

    var highScore: Int { UserDefaults.standard.integer(forKey: Self.highScoreKey(configuration.difficulty)) }
    static func highScoreKey(_ difficulty: SparringConfiguration.Difficulty) -> String { "sparring.highScore." + difficulty.rawValue }
    /// Stores the score if it beats the record; returns true for a new record.
    @discardableResult func commitHighScore() -> Bool {
        guard configuration.mode == .arcade, engine.score > highScore else { return false }
        UserDefaults.standard.set(engine.score, forKey: Self.highScoreKey(configuration.difficulty))
        return true
    }
}

extension PadBodyFrame {
    /// Same orientation as `like`, with a smoothed centre and scale.
    init?(centre: PadPoint, scale: Double, like frame: PadBodyFrame) {
        let half = frame.axis * (scale / 2)
        let left = PadCameraTransform.source(centre - half, aspect: frame.aspect)
        let right = PadCameraTransform.source(centre + half, aspect: frame.aspect)
        var points = [PadPoint?](repeating: nil, count: 17)
        points[5] = left; points[6] = right
        self.init(points: points, aspect: frame.aspect)
    }
}
