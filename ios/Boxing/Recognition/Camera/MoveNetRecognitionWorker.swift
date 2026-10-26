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
        var recoveredError: String? = nil
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
    /// One unscorable frame between scorable frames is held back, not discarded:
    /// at full extension toward the camera the wrist briefly foreshortens, and
    /// that is exactly the frame on which the punch event is emitted.
    private var deferred: (sample: BoxMaxxingKernel.Sample, captureMs: Double)?
    private var upperCrop = UpperBodyCrop()
    private var restartTimes: [Double] = []
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
            wristTrajectory = []; deferred = nil; upperCrop.reset()
            // With frame rotation pinned, rapid generation changes are recovery
            // restarts. Two within 30 s fall back to the proven full-frame input.
            restartTimes.append(started); restartTimes.removeAll { started - $0 > 30_000 }
            if restartTimes.count > 2 { upperCrop.disabled = true }
        }
        guard let runtime, let kernel else { throw MoveNetRuntime.Failure.creation }
        let mapping = frame.pixels.mapping
        let region = upperBodyOnly ? upperCrop.region(width: mapping.uprightWidth, height: mapping.uprightHeight)
            : try crop.crop(width: mapping.uprightWidth, height: mapping.uprightHeight)
        let plan = try MoveNetLetterbox(inputSize: runtime.inputSize, crop: region,
                                       uprightWidth: mapping.uprightWidth, uprightHeight: mapping.uprightHeight)
        let rgb = try MoveNetYUVConverter.rgb(frame: frame.pixels, plan: plan)
        let pose = try runtime.infer(rgb: rgb, plan: plan)
        // The person-crop tracker is only sized by crop(); in upper-body mode it
        // is never sized, and updating it would reject every frame.
        if upperBodyOnly { upperCrop.update(points: pose, width: mapping.uprightWidth, height: mapping.uprightHeight) }
        else { try crop.update(points: pose) }
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
        cueLock.lock(); let pendingHand = requestedCue?.hand; cueLock.unlock()
        // While a cue is open, only the requested arm and both shoulders must
        // be current. The guard hand sits beside the face and routinely drops
        // confidence; it must not void the punching arm's evidence.
        let scoringIDs: [Int]
        if let hand = currentCue?.hand ?? pendingHand {
            scoringIDs = BoxMaxxingJudge.limbs(hand: hand, stance: stance).first == .left ? [5, 6, 7, 9] : [5, 6, 8, 10]
        } else { scoringIDs = upperIDs }
        let currentPointsReliable = scoringIDs.allSatisfy { index in
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
        var events: [BoxMaxxingResponseBridge.Event] = []
        var cueInterruption: String?
        var cueUnjudged: String?
        var targetMatch: PadTargetMatch?
        var judgedID: UUID?
        var recoveredError: String?
        do {
            if response == nil { response = BoxMaxxingResponseBridge(kernel: kernel) }
            cueLock.lock(); let revision = cueRevision, request = requestedCue; cueLock.unlock()
            if revision != appliedRevision {
                try response?.suspend(atMs: finished); currentCue = nil; appliedRevision = revision; cueHadGap = false; cueGapReason = nil; wristTrajectory = []; deferred = nil
                if let request, request.generation == frame.generation, request.visibleMs <= finished {
                    let deadline = request.responseSeconds * 1000
                    let (token, _) = try response!.open(.init(id: request.id.uuidString, hand: request.hand, targetReps: 1,
                        timeoutMs: deadline, minConfidence: 0.6), atMs: request.visibleMs, generation: frame.generation)
                    try response?.presented(token, window: .init(tReadyMs: request.visibleMs, earlyGraceMs: BoxMaxxingJudge.defaultEarlyGraceMs,
                        failMs: deadline, greenMs: deadline * 0.65, yellowMs: deadline * 0.35))
                    currentCue = request
                }
            }
            judgedID = currentCue?.id
            if let cue = currentCue {
                if frame.timestampMs >= cue.visibleMs {
                    let limb = BoxMaxxingJudge.limbs(hand: cue.hand, stance: stance).first
                    let wristIndex = limb == .left ? 9 : 10, elbowIndex = limb == .left ? 7 : 8
                    // The punching arm uses the tracker's 0.2 armed-arm allowance:
                    // at full extension toward the camera its confidence dips.
                    let rawPoints: [PadPoint?] = pose.enumerated().map { index, point in
                        let minimum = index == wristIndex || index == elbowIndex ? 0.2 : 0.3
                        return point.score >= minimum && (0...1).contains(point.x) && (0...1).contains(point.y) ? .init(x: point.x, y: point.y) : nil
                    }
                    let aspect = Double(mapping.uprightWidth) / Double(mapping.uprightHeight)
                    let body = PadBodyFrame(points: rawPoints, aspect: aspect)
                    let fist = PadFist.point(wrist: rawPoints[wristIndex], elbow: rawPoints[elbowIndex], aspect: aspect)
                    wristTrajectory.append(.init(tMs: frame.timestampMs, wrist: fist, body: body,
                                                 reliable: processingIssue == nil && shouldersObserved && body != nil && fist != nil))
                    wristTrajectory.removeAll { frame.timestampMs - $0.tMs > 8000 }
                }
                if let rejected = sample.punches.first(where: { $0.rejected != nil })?.rejected {
                    // A rejected movement candidate is not a recognised punch and
                    // not proof of an absent response. Retain the chance for a clean
                    // response, then report uncertainty rather than a false timeout.
                    cueHadGap = true; cueGapReason = "candidate_" + rejected
                }
                let softlyObserved = processingIssue == nil && sample.status == "ok" && shouldersObserved && visibleForPolicy
                if let interruptionReason {
                    cueInterruption = interruptionReason; deferred = nil
                    try response?.suspend(atMs: finished); currentCue = nil
                } else if !canScore && deferred == nil && softlyObserved {
                    deferred = (sample, frame.timestampMs)
                } else if !canScore {
                    deferred = nil
                    // Retain cue and deadline across a brief dip. Never observe or
                    // tick the judge on this frame, and quarantine its action onset.
                    cueHadGap = true; cueGapReason = trackingIssue ?? "observation_uncertain"
                    response?.excludeActionsThrough(atMs: finished)
                    if let cue = currentCue, finished > cue.visibleMs + cue.responseSeconds * 1000 + BoxMaxxingJudge.deliveryGraceMs {
                        cueUnjudged = cueGapReason
                        try response?.suspend(atMs: finished); currentCue = nil
                    }
                } else {
                    let terminalKinds = ["rep_ok", "rep_wrong_hand", "rep_wrong_kind", "rep_timeout", "rep_unjudged"]
                    var judgedPunches = sample.punches
                    if let held = deferred {
                        deferred = nil
                        if case let .judged(result) = try response!.observe(held.sample, captureMs: held.captureMs, deliveredMs: finished,
                            generation: frame.generation, timingReliable: true, upperBodyObserved: upperBodyOnly) { events += result }
                        if events.contains(where: { terminalKinds.contains($0.kind) }) { judgedPunches = held.sample.punches }
                    }
                    if !events.contains(where: { terminalKinds.contains($0.kind) }),
                       case let .judged(result) = try response!.observe(sample, captureMs: frame.timestampMs, deliveredMs: finished,
                        generation: frame.generation, timingReliable: true, upperBodyObserved: upperBodyOnly) { events += result }
                    if !events.contains(where: { terminalKinds.contains($0.kind) }) { events += try response!.tick(atMs: finished) }
                    if let terminal = events.first(where: { terminalKinds.contains($0.kind) }) {
                        if terminal.kind == "rep_ok", let target = cue.target {
                            let onset = cue.visibleMs + (terminal.reactionMs ?? -Double.infinity)
                            let limb = BoxMaxxingJudge.limbs(hand: cue.hand, stance: stance).first
                            let candidate = judgedPunches.first {
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
        } catch {
            // A judge/bridge failure on one frame retries the cue; it must not
            // stop tracking. The kernel and pose remain valid for this frame.
            recoveredError = String(describing: error)
            cueLock.lock(); let pending = requestedCue; cueLock.unlock()
            if let id = currentCue?.id ?? pending?.id { judgedID = id; cueUnjudged = "judge_error" }
            events = []; targetMatch = nil; cueInterruption = nil
            response = nil; currentCue = nil; deferred = nil
        }
        return Observation(sample: sample, captureMs: frame.timestampMs, finishedMs: finished, processingMs: finished - started,
            sequence: frame.sequence, generation: frame.generation, timingReliable: frame.timestampSource == .captureHostClock,
            trackingIssue: trackingIssue, tracking: tracking, cueInterruption: cueInterruption, cueUnjudged: cueUnjudged,
            pose: pose, width: mapping.uprightWidth, height: mapping.uprightHeight, rotationDegrees: mapping.clockwiseDegrees,
            targetMatch: targetMatch, judgedCueID: judgedID, responseEvents: events, recoveredError: recoveredError)
    }
}
/// Square-ish region around the shoulders that keeps full straight-punch reach
/// (about three shoulder widths to each side) while feeding the model more
/// pixels per joint than the whole portrait frame. Falls back to the full
/// frame whenever both shoulders are not confidently seen.
struct UpperBodyCrop: Sendable {
    private var centre: (x: Double, y: Double)?
    private var side: Double?
    private var misses = 0
    var disabled = false
    mutating func reset() { centre = nil; side = nil; misses = 0 }
    func region(width: Int, height: Int) -> MoveNetCrop {
        guard !disabled, let centre, let side else { return MoveNetCrop(x: 0, y: 0, width: width, height: height) }
        let w = min(Double(width), side), h = min(Double(height), side)
        guard w < Double(width) * 0.98 || h < Double(height) * 0.98 else { return MoveNetCrop(x: 0, y: 0, width: width, height: height) }
        let x = min(max(0, centre.x - w / 2), Double(width) - w)
        let y = min(max(0, centre.y - h / 2), Double(height) - h)
        return MoveNetCrop(x: Int(x.rounded()), y: Int(y.rounded()), width: max(1, Int(w.rounded())), height: max(1, Int(h.rounded())))
    }
    mutating func update(points: [MoveNetPoint], width: Int, height: Int) {
        guard points.count == 17, width > 0, height > 0 else { return }
        let left = points[5], right = points[6]
        guard left.score >= 0.35, right.score >= 0.35 else {
            misses += 1
            if misses >= 6 { reset() }
            return
        }
        misses = 0
        let lx = left.x * Double(width), ly = left.y * Double(height)
        let rx = right.x * Double(width), ry = right.y * Double(height)
        let shoulders = hypot(rx - lx, ry - ly)
        guard shoulders > 12 else { return }
        let nextSide = min(max(shoulders * 6.2, Double(min(width, height)) * 0.5), Double(max(width, height)))
        let next = (x: (lx + rx) / 2, y: (ly + ry) / 2 + shoulders * 0.35)
        if let centre, let side {
            // Heavy smoothing: the region must not chase each punch.
            self.centre = (centre.x * 0.8 + next.x * 0.2, centre.y * 0.8 + next.y * 0.2)
            self.side = max(side * 0.85 + nextSide * 0.15, nextSide * 0.9)
        } else {
            centre = next; side = nextSide
        }
    }
}

#endif
