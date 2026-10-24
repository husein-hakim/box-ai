#if os(iOS)
import Foundation

/// One instance belongs to the frame adapter's serial inference queue.
/// Reuses the exact pose preprocess and full recovered reference kernel;
/// no frame is written to SwiftData or disk.
final class MoveNetRecognitionWorker: @unchecked Sendable {
    struct Observation: Sendable {
        let sample: BoxMaxxingKernel.Sample
        let captureMs: Double
        let finishedMs: Double
        let processingMs: Double
        let sequence: UInt64
        let generation: UInt64
        let timingReliable: Bool
        let trackingIssue: String?
        let tracking: Tracking
        let cueInterruption: String?
        let cueUnjudged: String?
        let pose: [MoveNetPoint]
        let width: Int
        let height: Int
        let rotationDegrees: Int
        let targetMatch: PadTargetMatch?
        let judgedCueID: UUID?
        let responseEvents: [BoxMaxxingResponseBridge.Event]
    }
    struct Tracking: Sendable {
        let bodyInView: Bool
        let calibration: String
        let processingIssue: String?
        let bodyIssue: String?
        let canScore: Bool
        let canStartCue: Bool
        let canContinue: Bool
        let interruptionReason: String?
    }
    struct PresentedCue: Sendable {
        let id: UUID
        let hand: BoxMaxxingJudge.Hand
        let generation: UInt64
        let visibleMs: Double
        let responseSeconds: Double
        var target: PadTargetDefinition? = nil
    }
    private let cueLock = NSLock()
    private var requestedCue: PresentedCue?
    private var cueRevision = 0
    private var appliedRevision = -1
    private var response: BoxMaxxingResponseBridge?
    private var currentCue: PresentedCue?
    /// UI commands are copied under a lock; all reference/judge calls stay on the inference queue.
    func setPresentedCue(_ cue: PresentedCue?) {
        cueLock.lock(); requestedCue = cue; cueRevision += 1; cueLock.unlock()
    }
    private let model: MoveNetRuntime.Model
    private var runtime: MoveNetRuntime?
    private var kernel: BoxMaxxingKernel?
    private var crop = MoveNetCropTracker()
    private var generation: UInt64?
    private var lastCaptureMs: Double?
    private var lastUpperGoodMs: Double?
    private var recoveryStartMs: Double?
    private var recoveryFrames = 0
    private var processingBadSinceMs: Double?
    private var ready = false
    private var cueHadGap = false
    private var cueGapReason: String?
    private var wristTrajectory: [PadWristSample] = []
    private let upperBodyOnly: Bool
    private let stance: BoxMaxxingJudge.Stance
    init(model: MoveNetRuntime.Model = .thunder, stance: BoxMaxxingJudge.Stance, upperBodyOnly: Bool = false) {
        self.model = model; self.stance = stance; self.upperBodyOnly = upperBodyOnly
        // Full source field for straight punches: a guard-fitted person crop
        // otherwise excludes a newly extended arm before it can be detected.
        crop.enabled = !upperBodyOnly
    }

    func process(_ frame: MoveNetCapturedFrame) throws -> Observation {
        let started = ProcessInfo.processInfo.systemUptime * 1000
        if runtime == nil { runtime = try MoveNetRuntime(model: model) }
        if kernel == nil { kernel = try BoxMaxxingKernel(); try kernel?.setStance(stance) }
        if generation != frame.generation {
            crop.reset(); try kernel?.reset(); generation = frame.generation; currentCue = nil; response = nil; appliedRevision = -1; lastCaptureMs = nil
            lastUpperGoodMs = nil; recoveryStartMs = nil; recoveryFrames = 0; processingBadSinceMs = nil; ready = false
            cueHadGap = false; cueGapReason = nil
            wristTrajectory = []
        }
        guard let runtime, let kernel else { throw MoveNetRuntime.Failure.creation }
        let mapping = frame.pixels.mapping
        let region = try crop.crop(width: mapping.uprightWidth, height: mapping.uprightHeight)
        let plan = try MoveNetLetterbox(inputSize: runtime.inputSize, crop: region,
                                       uprightWidth: mapping.uprightWidth, uprightHeight: mapping.uprightHeight)
        let rgb = try MoveNetYUVConverter.rgb(frame: frame.pixels, plan: plan)
        let pose = try runtime.infer(rgb: rgb, plan: plan)
        try crop.update(points: pose)
        let input = BoxMaxxingKernel.Input(tMs: frame.timestampMs, width: Double(mapping.uprightWidth), height: Double(mapping.uprightHeight),
            keypoints: pose.enumerated().map { index, point in
                // Hip hallucinations must not change shoulder-based scale when
                // the declared exercise needs only the upper body.
                upperBodyOnly && index >= 11 ? nil : BoxMaxxingTracker.RawPoint(x: point.x, y: point.y, score: point.score)
            }, source: "avfoundation-movenet", model: model.rawValue,
            trackingGeneration: frame.generation, mirrored: false)
        let sample = try kernel.push(input)
        let finished = ProcessInfo.processInfo.systemUptime * 1000
        let processingIssue: String?
        if frame.timestampSource != .captureHostClock { processingIssue = "capture_clock" }
        else if finished < frame.timestampMs || finished - frame.timestampMs >= 400 { processingIssue = "inference_stale" }
        else if lastCaptureMs.map({ frame.timestampMs - $0 >= 400 }) == true { processingIssue = "capture_gap" }
        else { processingIssue = nil }
        lastCaptureMs = frame.timestampMs
        if processingIssue != nil {
            if processingBadSinceMs == nil { processingBadSinceMs = finished }
        } else { processingBadSinceMs = nil }
        let processingBlocked = processingBadSinceMs.map { finished - $0 >= 800 } ?? false
        let upperIDs = [5, 6, 7, 8, 9, 10]
        func observed(_ index: Int) -> Bool {
            let point = pose[index]
            return point.score >= 0.3 && (0...1).contains(point.x) && (0...1).contains(point.y)
        }
        let upperObserved = upperIDs.allSatisfy(observed)
        let shouldersObserved = [5, 6].allSatisfy(observed)
        if upperObserved && processingIssue == nil { lastUpperGoodMs = frame.timestampMs }
        // A bounded visibility hold, not permission to score held landmarks.
        let bodyInView = processingIssue != nil ? lastUpperGoodMs != nil :
            (upperObserved || lastUpperGoodMs.map { frame.timestampMs - $0 <= 350 } == true)
        let bodyIssue = processingIssue != nil || upperObserved ? nil : (shouldersObserved ? "body_arms" : "body_shoulders")
        let visibleForPolicy = upperBodyOnly ? bodyInView : sample.presence?.supportsUpperBody == true
        let currentPointsReliable = upperIDs.allSatisfy { index in
            // Preserve the recovered tracker's existing 0.2/150 ms armed-arm
            // allowance. It must itself accept a CURRENT observation; neither
            // held points nor its weaker prediction fallback can be scored.
            let minimum = index == 5 || index == 6 ? 0.3 : 0.2
            let point = pose[index], tracked = sample.frame.points[index]
            return tracked.observed && tracked.score >= minimum && point.score >= minimum &&
                (0...1).contains(point.x) && (0...1).contains(point.y)
        }
        let canScore = processingIssue == nil && sample.status == "ok" && !sample.frame.lost &&
            shouldersObserved && currentPointsReliable && visibleForPolicy
        if canScore {
            if recoveryStartMs == nil { recoveryStartMs = frame.timestampMs }
            recoveryFrames += 1
            if recoveryFrames >= 3 && frame.timestampMs - (recoveryStartMs ?? frame.timestampMs) >= 200 { ready = true }
        } else if !visibleForPolicy || processingBlocked || sample.status != "ok" {
            ready = false; recoveryStartMs = nil; recoveryFrames = 0
        }
        let interruptionReason: String?
        if processingBlocked { interruptionReason = processingIssue ?? "processing_delayed" }
        else if !visibleForPolicy { interruptionReason = bodyIssue ?? "body_framing" }
        else if sample.status != "ok" { interruptionReason = "calibration_" + sample.status }
        else { interruptionReason = nil }
        let tracking = Tracking(bodyInView: bodyInView, calibration: sample.status, processingIssue: processingIssue,
            bodyIssue: bodyIssue, canScore: canScore, canStartCue: ready && canScore && upperObserved,
            canContinue: ready && interruptionReason == nil, interruptionReason: interruptionReason)
        let trackingIssue = processingIssue ?? (sample.status != "ok" ? "calibration_" + sample.status :
            bodyIssue ?? (sample.frame.lost ? "pose_scale_unstable" : (!currentPointsReliable ? "held_arm_points" : nil)))
        if response == nil { response = BoxMaxxingResponseBridge(kernel: kernel) }
        cueLock.lock(); let revision = cueRevision, request = requestedCue; cueLock.unlock()
        if revision != appliedRevision {
            try response?.suspend(atMs: finished); currentCue = nil; appliedRevision = revision; cueHadGap = false; cueGapReason = nil; wristTrajectory = []
            if let request, request.generation == frame.generation, request.visibleMs <= finished {
                let deadline = request.responseSeconds * 1000
                let (token, _) = try response!.open(.init(id: request.id.uuidString, hand: request.hand, targetReps: 1,
                    timeoutMs: deadline, minConfidence: 0.6), atMs: request.visibleMs, generation: frame.generation)
                try response?.presented(token, window: .init(tReadyMs: request.visibleMs, earlyGraceMs: BoxMaxxingJudge.defaultEarlyGraceMs,
                    failMs: deadline, greenMs: deadline * 0.65, yellowMs: deadline * 0.35))
                currentCue = request
            }
        }
        var events: [BoxMaxxingResponseBridge.Event] = []
        var cueInterruption: String?
        var cueUnjudged: String?
        var targetMatch: PadTargetMatch?
        let judgedID = currentCue?.id
        if let cue = currentCue {
            if frame.timestampMs >= cue.visibleMs {
                let limb = BoxMaxxingJudge.limbs(hand: cue.hand, stance: stance).first
                let wristIndex = limb == .left ? 9 : 10
                let rawPoints: [PadPoint?] = pose.map { $0.score >= 0.3 && (0...1).contains($0.x) && (0...1).contains($0.y) ? .init(x: $0.x, y: $0.y) : nil }
                let body = PadBodyFrame(points: rawPoints, aspect: Double(mapping.uprightWidth) / Double(mapping.uprightHeight))
                wristTrajectory.append(.init(tMs: frame.timestampMs, wrist: rawPoints[wristIndex], body: body,
                                             reliable: canScore && rawPoints[wristIndex] != nil))
                wristTrajectory.removeAll { frame.timestampMs - $0.tMs > 8000 }
            }
            if let rejected = sample.punches.first(where: { $0.rejected != nil })?.rejected {
                // A rejected movement candidate is not a recognised punch and
                // not proof of an absent response. Retain the chance for a clean
                // response, then report uncertainty rather than a false timeout.
                cueHadGap = true; cueGapReason = "candidate_" + rejected
            }
            if let interruptionReason {
                cueInterruption = interruptionReason
                try response?.suspend(atMs: finished); currentCue = nil
            } else if !canScore {
                // Retain cue and deadline across a brief dip. Never observe or
                // tick the judge on this frame, and quarantine its action onset.
                cueHadGap = true; cueGapReason = trackingIssue ?? "observation_uncertain"
                response?.excludeActionsThrough(atMs: finished)
                if let cue = currentCue, finished > cue.visibleMs + cue.responseSeconds * 1000 + BoxMaxxingJudge.deliveryGraceMs {
                    cueUnjudged = cueGapReason
                    try response?.suspend(atMs: finished); currentCue = nil
                }
            } else {
                if case let .judged(result) = try response!.observe(sample, captureMs: frame.timestampMs, deliveredMs: finished,
                    generation: frame.generation, timingReliable: true, upperBodyObserved: upperBodyOnly) { events += result }
                let terminalKinds = ["rep_ok", "rep_wrong_hand", "rep_wrong_kind", "rep_timeout", "rep_unjudged"]
                if !events.contains(where: { terminalKinds.contains($0.kind) }) { events += try response!.tick(atMs: finished) }
                if let terminal = events.first(where: { terminalKinds.contains($0.kind) }) {
                    if terminal.kind == "rep_ok", let target = cue.target {
                        let onset = cue.visibleMs + (terminal.reactionMs ?? -Double.infinity)
                        let limb = BoxMaxxingJudge.limbs(hand: cue.hand, stance: stance).first
                        let candidate = sample.punches.first {
                            $0.rejected == nil && $0.candidate.limb == limb &&
                            (terminal.actionId == nil ? abs($0.candidate.tOnsetMs - onset) < 1 : $0.candidate.actionId == terminal.actionId)
                        }?.candidate
                        if target.cueID == cue.id && target.generation == frame.generation && target.hand == cue.hand {
                            targetMatch = PadTargetJudge.judge(target: target, peakMs: candidate?.tPeakMs, onsetMs: candidate?.tOnsetMs ?? onset, samples: wristTrajectory)
                        } else {
                            targetMatch = .init(outcome: .uncertain, target: target, closestWrist: nil, peakMs: nil, reason: "stale_target_geometry")
                        }
                    }
                    if terminal.kind == "rep_unjudged" {
                        cueUnjudged = "judge_" + (terminal.reason ?? "unjudged"); events = []
                    } else if terminal.kind == "rep_timeout" && cueHadGap {
                        cueUnjudged = cueGapReason ?? "observation_gap"; events = []
                    }
                    try response?.suspend(atMs: finished); currentCue = nil
                }
            }
        }
        return Observation(sample: sample, captureMs: frame.timestampMs, finishedMs: finished, processingMs: finished - started,
            sequence: frame.sequence, generation: frame.generation, timingReliable: frame.timestampSource == .captureHostClock,
            trackingIssue: trackingIssue, tracking: tracking, cueInterruption: cueInterruption, cueUnjudged: cueUnjudged,
            pose: pose, width: mapping.uprightWidth, height: mapping.uprightHeight, rotationDegrees: mapping.clockwiseDegrees,
            targetMatch: targetMatch, judgedCueID: judgedID, responseEvents: events)
    }
}
#endif
