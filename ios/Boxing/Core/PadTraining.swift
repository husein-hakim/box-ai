import Foundation

/// Product pacing and guidance, not changes to the recovered recognizer's thresholds.
enum PadLevel: String, CaseIterable, Codable, Identifiable, Sendable {
    case beginner, intermediate, advanced
    var id: Self { self }
    var title: String { rawValue.capitalized }
    static func suggested(experience: String) -> Self {
        switch experience { case "Experienced": .advanced; case "Some experience": .intermediate; default: .beginner }
    }
    var responseSeconds: Double { switch self { case .beginner: 6; case .intermediate: 3; case .advanced: 1.8 } }
    var resetSeconds: Double { switch self { case .beginner: 2.5; case .intermediate: 1.5; case .advanced: 1 } }
    var explanation: String {
        switch self {
        case .beginner: "Large aim guides, hand labels and step-by-step reminders. Six seconds to respond, then a relaxed reset."
        case .intermediate: "Clear pad targets with shorter prompts. Three seconds to respond and more continuous practice."
        case .advanced: "Compact targets and brief callouts. A 1.8-second response window and a short reset."
        }
    }
}

struct PadConfiguration: Codable, Equatable, Sendable {
    enum Mode: String, CaseIterable, Codable, Sendable { case learn, rounds }
    var mode: Mode = .learn
    var level: PadLevel = .beginner
    var stance: BoxMaxxingJudge.Stance = .orthodox
    var activityID: String? = nil
    var rounds = 2
    var workSeconds = 60
    var restSeconds = 30
    var attempts = 8
    var targetMode: PadTargetMode? = .accuracy
    // Missing in older records/drafts: preserve their recognition-only behavior.
    var effectiveTargetMode: PadTargetMode { targetMode ?? .reaction }
    var isValid: Bool {
        (1...6).contains(rounds) && (20...180).contains(workSeconds) && (0...120).contains(restSeconds) && (rounds == 1 || restSeconds >= 15) &&
        (4...24).contains(attempts) && (activityID == nil || Self.supportedIDs.contains(activityID!))
    }
    static let supportedIDs = ["jab-reset-v1", "cross-reset-v1", "jab-cross-reset-v1"]
    var title: String { mode == .rounds ? "Live pad rounds" : "Camera practice · " + (ActivityCatalog.find(activityID ?? "jab-cross-reset-v1")?.title ?? "Straight punches") }
    func hand(for index: Int) -> BoxMaxxingJudge.Hand {
        if activityID == "jab-reset-v1" { return .lead }
        if activityID == "cross-reset-v1" { return .rear }
        return index.isMultiple(of: 2) ? .lead : .rear
    }
}

struct PadAttempt: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let hand: BoxMaxxingJudge.Hand
    let outcome: String
    let reactionMs: Double?
    var targetMatch: PadTargetMatch? = nil
    var isHit: Bool { outcome == "hit_green" || outcome == "hit_yellow" }
    var countsTowardDrill: Bool { targetMatch?.outcome != .uncertain }
    var title: String {
        if isHit, let targetMatch {
            let punch = hand == .lead ? "Jab" : "Cross"
            switch targetMatch.outcome {
            case .reached: return punch + " recognised · target reached"
            case .missed: return punch + " recognised · target missed"
            case .uncertain: return punch + " recognised · aim unclear—retry"
            }
        }
        return switch outcome {
        case "hit_green", "hit_yellow": hand == .lead ? "Jab recognised" : "Cross recognised"
        case "wrong_hand": "Wrong hand"
        case "wrong_kind": "Straight punch requested"
        case "early": "Moved before the cue"
        default: "No response detected"
        }
    }
}

struct PadRetry: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let hand: BoxMaxxingJudge.Hand
    let reason: String
}

enum PadTrackingGuidance {
    static func isProcessing(_ reason: String) -> Bool {
        ["capture_clock", "inference_stale", "capture_gap", "processing_delayed", "ui_delivery_stale", "ui_tick_gap", "worker_error", "camera_error"].contains(reason)
    }
    static func instruction(_ reason: String) -> String { String(localized: message(reason)) }
    private static func message(_ reason: String) -> LocalizedStringResource {
        switch reason {
        case "calibration_too_far": "Move a little closer."
        case "calibration_too_close": "Move a little farther back."
        case "calibration_hold_still": "Hold your guard briefly to calibrate."
        case "calibration_partial", "calibration_nobody": "Keep your head, both shoulders and arms in view."
        case "capture_clock": "Camera timing is uncertain—pause and retry."
        case "inference_stale", "capture_gap", "processing_delayed", "ui_delivery_stale", "ui_tick_gap": "Camera processing is delayed—pause and retry."
        case "worker_error", "camera_error": "Camera tracking stopped—pause and retry."
        case "camera_interrupted": "Camera paused. Wait for it to resume."
        case "source_generation", "camera_restarting": "The camera view changed. Hold your guard briefly."
        default: "Keep both shoulders and arms in view."
        }
    }
}

/// Local metadata only: no images, landmark coordinates or inferred technique.
struct PadCameraDiagnostics: Codable, Sendable {
    var interruptionEpisodes: Int? = 0
    var interruptionCauses: [String: Int]? = [:]
    var legacyPresenceDisagreements: Int? = 0
    var frames = 0
    var frameIssues: [String: Int] = [:]
    var generationChanges = 0
    var rejectedDeliveries = 0
    var maxCaptureAgeMs = 0.0
    var maxProcessingMs = 0.0
    var maxDeliveryMs = 0.0
}

struct PadTrainingDiagnostics: Codable, Sendable {
    var trackingEpisodes = 0
    var episodeCauses: [String: Int] = [:]
    var retryCauses: [String: Int] = [:]
    var camera = PadCameraDiagnostics()
}

struct PadTrainingState: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case briefing, calibrating, work, rest, paused, recap }
    enum FeedbackStage { case ready, cue, outcome, reset, retry }
    let configuration: PadConfiguration
    private(set) var phase: Phase = .briefing
    private(set) var attempts: [PadAttempt] = []
    private(set) var uncertainAttempts = 0
    private(set) var retries: [PadRetry]? = []
    private(set) var activeSeconds = 0.0
    private(set) var workSeconds = 0.0
    private(set) var roundSeconds = 0.0
    private(set) var round = 1
    private(set) var completedRounds = 0
    private(set) var endedEarly = false
    private(set) var cueID: UUID?
    private(set) var cuePresented = false
    private(set) var hand: BoxMaxxingJudge.Hand = .lead
    private(set) var feedback = "Find your stance."
    // Optional additive payload preserves older saved practices without relabelling their counter.
    var diagnostics: PadTrainingDiagnostics? = .init()
    private(set) var feedbackStage: FeedbackStage = .ready
    private(set) var feedbackID: UUID?
    private(set) var feedbackDetail: String?
    var feedbackIsRecognised: Bool { feedbackID == attempts.last?.id && attempts.last?.isHit == true }
    var completedAttempts: Int { attempts.filter(\.countsTowardDrill).count }
    var feedbackSucceeded: Bool { feedbackIsRecognised && attempts.last?.targetMatch?.outcome != .missed && attempts.last?.targetMatch?.outcome != .uncertain }
    var spokenFeedback: String {
        guard let feedbackDetail, feedbackDetail != feedback else { return feedback }
        return feedback + ". " + feedbackDetail
    }
    private var feedbackUntil: Double?
    private var cueIndex = 0
    private var lastTick: Double?
    private var nextCueAt: Double?
    private var phaseBeforePause: Phase?
    private enum CodingKeys: String, CodingKey {
        case configuration, phase, attempts, uncertainAttempts, activeSeconds, workSeconds, roundSeconds,
             round, completedRounds, endedEarly, hand, feedback, cueIndex, phaseBeforePause, diagnostics, retries
    }
    init(configuration: PadConfiguration) { self.configuration = configuration; hand = configuration.hand(for: 0) }
    var status: RoundTimeline.Status {
        switch phase { case .briefing: .ready; case .paused: .paused; case .recap: endedEarly ? .stopped : .finished; default: .running }
    }
    var isValidCheckpoint: Bool {
        configuration.isValid && attempts.count <= 10000 && (retries?.count ?? 0) <= 10000 && uncertainAttempts >= 0 && (0...10000).contains(cueIndex) &&
        [activeSeconds, workSeconds, roundSeconds].allSatisfy { $0.isFinite && $0 >= 0 } && workSeconds <= activeSeconds + 0.001 &&
        round >= 1 && round <= configuration.rounds && completedRounds >= 0 && completedRounds <= configuration.rounds &&
        Set(attempts.map(\.id)).count == attempts.count && attempts.allSatisfy { ["hit_green", "hit_yellow", "wrong_hand", "wrong_kind", "miss_timeout", "early"].contains($0.outcome) && ($0.reactionMs.map { $0.isFinite && abs($0) < 60000 } ?? true) }
    }
    func restored() -> Self {
        var copy = self
        copy.cueID = nil; copy.cuePresented = false; copy.lastTick = nil; copy.nextCueAt = nil
        copy.feedbackUntil = nil; copy.feedbackStage = .ready; copy.feedbackID = nil; copy.feedbackDetail = nil
        if phase != .briefing && phase != .recap {
            copy.phaseBeforePause = phase == .paused ? phaseBeforePause : phase
            copy.phase = .paused; copy.feedback = "Resume, then hold your guard to recalibrate."
        }
        return copy
    }
    mutating func begin() { guard phase == .briefing else { return }; phase = .calibrating; lastTick = nil }
    mutating func targetSetupRequired() {
        guard phase == .work, feedbackStage == .cue, !cuePresented else { return }
        cueIndex = max(0, cueIndex - 1); cueID = nil; nextCueAt = nil; lastTick = nil
        phase = .calibrating; feedbackStage = .ready; feedback = "Recheck your guard and calibrated reach."
        feedbackDetail = nil
    }
    mutating func trackingLost(reason: String = "tracking_unclear", at now: Double? = nil) {
        guard phase == .work || phase == .calibrating else { return }
        // Once judged, an outcome owns the screen until its hold finishes.
        guard feedbackStage != .outcome && feedbackStage != .reset else { return }
        if phase == .work {
            diagnostics?.trackingEpisodes += 1
            diagnostics?.episodeCauses[reason, default: 0] += 1
        }
        if cueID != nil {
            cueIndex = max(0, cueIndex - 1) // Retry the same requested hand.
            if cuePresented {
                uncertainAttempts += 1
                diagnostics?.retryCauses[reason, default: 0] += 1
            }
        }
        cueID = nil; cuePresented = false; nextCueAt = nil; lastTick = nil
        phase = .calibrating
        if feedbackStage != .retry {
            feedbackStage = .retry; feedbackUntil = now.map { $0 + 2.6 }
            feedback = PadTrackingGuidance.isProcessing(reason) || reason.hasPrefix("calibration_") ?
                PadTrackingGuidance.instruction(reason) : "Tracking lost—let’s retry"
            feedbackDetail = PadTrackingGuidance.instruction(reason)
        }
    }
    mutating func tick(at now: Double, trackingReady: Bool, trackingReason: String = "tracking_unclear", speechBusy: Bool = false,
                       cueingReady: Bool? = nil, scoringReady: Bool? = nil) {
        guard now.isFinite else { return }
        if feedbackStage == .outcome || feedbackStage == .reset {
            countFeedbackTime(at: now, trackingReady: scoringReady ?? trackingReady)
        }
        if feedbackStage == .outcome {
            guard let deadline = feedbackUntil, now >= deadline, !speechBusy else { return }
            feedbackStage = .reset; feedback = "Reset to guard"; feedbackDetail = nil
            feedbackUntil = now + configuration.level.resetSeconds
            lastTick = nil
            return
        }
        if feedbackStage == .reset {
            guard now >= (feedbackUntil ?? now), !speechBusy else { return }
            if configuration.mode == .learn && completedAttempts >= configuration.attempts {
                phase = .recap; completedRounds = 1; return
            }
            feedbackStage = .ready; feedbackUntil = nil
            feedback = "Ready. Wait for the pad."
            nextCueAt = now + 1
        }
        if feedbackStage == .retry {
            if PadTrackingGuidance.isProcessing(trackingReason) || trackingReason.hasPrefix("calibration_") {
                feedback = PadTrackingGuidance.instruction(trackingReason); feedbackDetail = nil
            } else if trackingReason.hasPrefix("body_") {
                feedback = "Tracking lost—let’s retry"; feedbackDetail = PadTrackingGuidance.instruction(trackingReason)
            }
            guard cueingReady ?? trackingReady, now >= (feedbackUntil ?? now), !speechBusy else { lastTick = nil; return }
            feedbackStage = .reset; feedback = "Reset to guard"; feedbackDetail = nil
            feedbackUntil = now + configuration.level.resetSeconds
            return
        }
        if phase == .calibrating {
            guard cueingReady ?? trackingReady, now >= (feedbackUntil ?? now), !speechBusy else { lastTick = nil; return }
            feedbackStage = .ready; feedbackUntil = nil
            phase = .work; nextCueAt = now + 1; lastTick = now; feedback = "Ready. Watch the pad."
        }
        guard phase == .work || phase == .rest else { return }
        if phase == .work && !trackingReady { trackingLost(reason: trackingReason, at: now); return }
        if phase == .work && !(scoringReady ?? trackingReady) { lastTick = nil; return }
        var delta = lastTick.map { max(0, now - $0) } ?? 0
        // Never grant time across a suspended run loop or missing observation period.
        guard delta <= 0.75 else { lastTick = nil; if phase == .work { trackingLost(reason: "ui_tick_gap", at: now) }; return }
        if phase == .work && configuration.mode == .rounds { delta = min(delta, max(0, Double(configuration.workSeconds) - roundSeconds)) }
        lastTick = now; activeSeconds += delta; roundSeconds += delta
        if phase == .rest {
            if roundSeconds >= Double(configuration.restSeconds) { round += 1; roundSeconds = 0; phase = .calibrating; lastTick = nil }
            return
        }
        workSeconds += delta
        if configuration.mode == .rounds && roundSeconds >= Double(configuration.workSeconds) {
            // Finish an already presented response, including its visible
            // outcome/reset, before a round boundary can replace the screen.
            guard cueID == nil else { return }
            completedRounds += 1; cueID = nil; cuePresented = false; lastTick = nil
            if round >= configuration.rounds { phase = .recap } else { phase = .rest; roundSeconds = 0; feedback = "Rest. Breathe and reset." }
            return
        }
        if cueID == nil && now >= (nextCueAt ?? now) && !speechBusy && (cueingReady ?? trackingReady) {
            hand = configuration.hand(for: cueIndex); cueIndex += 1
            cueID = UUID(); cuePresented = false; feedbackStage = .cue; feedback = hand == .lead ? "Jab" : "Cross"
        }
    }
    private mutating func countFeedbackTime(at now: Double, trackingReady: Bool) {
        guard phase == .work, trackingReady else { lastTick = nil; return }
        let elapsed = lastTick.map { max(0, now - $0) } ?? 0
        lastTick = now
        guard elapsed <= 0.75 else { return }
        let delta = configuration.mode == .rounds ? min(elapsed, max(0, Double(configuration.workSeconds) - roundSeconds)) : elapsed
        activeSeconds += delta; workSeconds += delta; roundSeconds += delta
    }
    @discardableResult mutating func presented(_ id: UUID) -> Bool {
        guard phase == .work, cueID == id, !cuePresented else { return false }
        cuePresented = true; return true
    }
    @discardableResult mutating func resolve(id: UUID, outcome: String, reactionMs: Double?, at now: Double, targetMatch: PadTargetMatch? = nil) -> Bool {
        guard phase == .work, cueID == id, cuePresented, !attempts.contains(where: { $0.id == id }),
              now.isFinite, ["hit_green", "hit_yellow", "wrong_hand", "wrong_kind", "miss_timeout", "early"].contains(outcome) else { return false }
        guard targetMatch.map({ $0.target.cueID == id && $0.target.hand == hand }) ?? true else { return false }
        attempts.append(.init(id: id, hand: hand, outcome: outcome, reactionMs: reactionMs.flatMap { $0.isFinite ? $0 : nil }, targetMatch: targetMatch))
        cueID = nil; cuePresented = false; nextCueAt = nil; lastTick = nil
        feedbackStage = .outcome; feedbackUntil = nil
        feedbackID = id; feedbackDetail = targetMatch?.hint; feedback = attempts.last!.title
        if targetMatch?.outcome == .uncertain {
            cueIndex = max(0, cueIndex - 1); uncertainAttempts += 1
            if retries == nil { retries = [] }
            retries?.append(.init(id: id, hand: hand, reason: "target_" + (targetMatch?.reason ?? "uncertain")))
            diagnostics?.retryCauses["target_" + (targetMatch?.reason ?? "uncertain"), default: 0] += 1
            feedbackDetail = "The punch was recognised, but aiming evidence was unclear. Retry the same hand; this is not a target miss."
        }
        return true
    }
    /// Recognition uncertainty is a visible result, not a body-loss event or
    /// judged miss. Preserve the hand sequence and avoid restarting calibration.
    @discardableResult mutating func retryResponse(id: UUID, reason: String, at now: Double) -> Bool {
        guard phase == .work, cueID == id, cuePresented, now.isFinite else { return false }
        if retries == nil { retries = [] }
        retries?.append(.init(id: id, hand: hand, reason: reason))
        uncertainAttempts += 1; diagnostics?.retryCauses["response_uncertain/" + reason, default: 0] += 1
        cueIndex = max(0, cueIndex - 1)
        cueID = nil; cuePresented = false; nextCueAt = nil; lastTick = nil
        feedbackStage = .outcome; feedbackUntil = nil; feedbackID = id
        let punch = hand == .lead ? "Jab" : "Cross"
        if reason.hasPrefix("candidate_") || reason.hasPrefix("judge_") {
            feedback = punch + " movement not recognised—retry"
            feedbackDetail = "The movement could not be recognised reliably. Retry the same hand; this is not a missed response."
        } else {
            feedback = punch + " tracking too uncertain—retry"
            feedbackDetail = PadTrackingGuidance.isProcessing(reason) ? PadTrackingGuidance.instruction(reason) :
                "Tracking evidence was insufficient to judge this response. Retry the same hand; this is not a miss."
        }
        return true
    }
    /// Hold starts at the result renderer's submission acknowledgement, never
    /// at inference completion or an asynchronously delivered view update.
    @discardableResult mutating func feedbackPresented(id: UUID, at now: Double) -> Bool {
        guard feedbackStage == .outcome, feedbackID == id, feedbackUntil == nil, now.isFinite else { return false }
        feedbackUntil = now + 2.6
        return true
    }
    mutating func pause() {
        guard phase != .briefing && phase != .recap && phase != .paused else { return }
        phaseBeforePause = phase; phase = .paused; cueID = nil; cuePresented = false; lastTick = nil; nextCueAt = nil
        feedbackUntil = nil; feedbackStage = .ready
        feedbackID = nil; feedbackDetail = nil
    }
    mutating func resume() {
        guard phase == .paused else { return }
        phase = phaseBeforePause == .rest ? .rest : .calibrating
        lastTick = nil; nextCueAt = nil; feedback = "Hold your guard. We’ll recheck tracking before continuing."
        if configuration.mode == .learn, completedAttempts >= configuration.attempts, let last = attempts.last {
            feedbackStage = .outcome; feedbackUntil = nil; feedbackID = last.id; feedback = last.title
        }
    }
    mutating func stop() { guard phase != .recap else { return }; endedEarly = true; phase = .recap; cueID = nil; cuePresented = false; lastTick = nil }
}

/// Explicit letterbox/mirror mapping matching the preview's full-source field.
struct PadPreviewMapping {
    static func point(_ point: CGPoint, image: CGSize, viewport: CGSize) -> CGPoint {
        PadCameraTransform(image: image, viewport: viewport).screen(.init(x: point.x, y: point.y))
    }
}

