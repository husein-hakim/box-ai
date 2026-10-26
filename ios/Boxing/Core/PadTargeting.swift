import Foundation

enum PadTargetMode: String, Codable, CaseIterable, Sendable {
    case accuracy, reaction
    var title: String { self == .accuracy ? "Target accuracy" : "Reaction only" }
}

/// Unmirrored source-image coordinates unless explicitly converted to metric.
struct PadPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    static func + (a: Self, b: Self) -> Self { .init(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: Self, b: Self) -> Self { .init(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: Self, b: Double) -> Self { .init(x: a.x * b, y: a.y * b) }
    func dot(_ b: Self) -> Double { x * b.x + y * b.y }
    var length: Double { hypot(x, y) }
}

/// One transform: full upright source, aspect FILL (edge-to-edge camera),
/// front-camera mirror exactly once. Preview frame, joints, targets and
/// target-distance math all use it; anything outside the viewport is off-screen.
struct PadCameraTransform {
    let image: CGSize
    let viewport: CGSize
    var imageRect: CGRect {
        guard image.width > 0, image.height > 0 else { return .zero }
        let scale = max(viewport.width / image.width, viewport.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2, width: size.width, height: size.height)
    }
    func screen(_ source: PadPoint) -> CGPoint {
        let rect = imageRect
        return .init(x: rect.minX + (1 - source.x) * rect.width, y: rect.minY + source.y * rect.height)
    }
    func source(_ screen: CGPoint) -> PadPoint {
        let rect = imageRect
        guard rect.width > 0, rect.height > 0 else { return .init(x: 0, y: 0) }
        return .init(x: 1 - (screen.x - rect.minX) / rect.width, y: (screen.y - rect.minY) / rect.height)
    }
    static func metric(_ source: PadPoint, aspect: Double) -> PadPoint { .init(x: source.x * aspect, y: source.y) }
    static func source(_ metric: PadPoint, aspect: Double) -> PadPoint { .init(x: metric.x / aspect, y: metric.y) }
    /// The whole aim region is on screen with a small margin.
    func isVisible(_ target: PadTargetDefinition, margin: CGFloat = 8) -> Bool {
        CGRect(origin: .zero, size: viewport).insetBy(dx: margin, dy: margin).contains(region(target))
    }
    func region(_ target: PadTargetDefinition) -> CGRect {
        let centre = screen(target.centre)
        let radius = target.radius * imageRect.height
        return .init(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2)
    }
}

/// The fighter aims with the knuckles, but pose models report the wrist joint.
/// Extend the wrist along the forearm to estimate the fist's centre. Used for
/// reach capture, displayed pads and judging alike, so all three agree.
enum PadFist {
    static let forearmExtension = 0.3
    static func point(wrist: PadPoint?, elbow: PadPoint?, aspect: Double) -> PadPoint? {
        guard let wrist else { return nil }
        guard let elbow, aspect > 0 else { return wrist }
        let w = PadCameraTransform.metric(wrist, aspect: aspect), e = PadCameraTransform.metric(elbow, aspect: aspect)
        return PadCameraTransform.source(w + (w - e) * forearmExtension, aspect: aspect)
    }
    /// Copy of a 17-point pose with both wrists replaced by fist estimates.
    static func aimPoints(_ points: [PadPoint?], aspect: Double) -> [PadPoint?] {
        guard points.count == 17 else { return points }
        var result = points
        result[9] = point(wrist: points[9], elbow: points[7], aspect: aspect)
        result[10] = point(wrist: points[10], elbow: points[8], aspect: aspect)
        return result
    }
}

struct PadBodyFrame: Codable, Equatable, Sendable {
    let centre: PadPoint
    let axis: PadPoint
    let down: PadPoint
    let scale: Double
    let aspect: Double
    init?(points: [PadPoint?], aspect: Double) {
        guard points.count == 17, let left = points[5], let right = points[6], aspect > 0 else { return nil }
        let l = PadCameraTransform.metric(left, aspect: aspect), r = PadCameraTransform.metric(right, aspect: aspect)
        let width = (r - l).length
        guard width > 0.04 else { return nil }
        centre = (l + r) * 0.5; scale = width; self.aspect = aspect
        axis = (r - l) * (1 / width)
        let perpendicular = PadPoint(x: -axis.y, y: axis.x)
        down = perpendicular.y >= 0 ? perpendicular : perpendicular * -1
    }
    func local(_ source: PadPoint) -> PadPoint {
        let delta = PadCameraTransform.metric(source, aspect: aspect) - centre
        return .init(x: delta.dot(axis) / scale, y: delta.dot(down) / scale)
    }
    func source(_ local: PadPoint) -> PadPoint {
        PadCameraTransform.source(centre + (axis * local.x + down * local.y) * scale, aspect: aspect)
    }
    func compatible(with other: Self, scaleTolerance: Double = 0.25) -> Bool {
        abs(other.aspect - aspect) < 0.001 && abs(other.scale / scale - 1) <= scaleTolerance && axis.dot(other.axis) >= 0.94
    }
}

struct PadTargetDefinition: Codable, Equatable, Sendable {
    let cueID: UUID
    let calibrationID: UUID
    let generation: UInt64
    let hand: BoxMaxxingJudge.Hand
    let centre: PadPoint
    let origin: PadPoint
    /// Radius in source-image-height units: a real circle despite image aspect.
    let radius: Double
    let body: PadBodyFrame
    var fitsSource: Bool {
        centre.x - radius / body.aspect >= 0 && centre.x + radius / body.aspect <= 1 &&
        centre.y - radius >= 0 && centre.y + radius <= 1
    }
    func distance(_ source: PadPoint) -> Double {
        (PadCameraTransform.metric(source - centre, aspect: body.aspect)).length
    }
}

struct PadTargetMatch: Codable, Equatable, Sendable {
    enum Outcome: String, Codable, Sendable { case reached, missed, uncertain }
    let outcome: Outcome
    let target: PadTargetDefinition
    let closestWrist: PadPoint?
    let peakMs: Double?
    let reason: String?
    var hint: String? {
        guard outcome == .missed, let closestWrist else { return nil }
        let delta = PadCameraTransform.metric(closestWrist - target.centre, aspect: target.body.aspect)
        if abs(delta.y) >= abs(delta.x) { return delta.y < 0 ? "Aim a little lower toward the ring." : "Aim a little higher toward the ring." }
        // Source is unmirrored; the displayed front-camera image is mirrored.
        return delta.x > 0 ? "Aim a little to the right of where that punch travelled." : "Aim a little to the left of where that punch travelled."
    }
}

struct PadWristSample: Sendable {
    let tMs: Double
    let wrist: PadPoint?
    let body: PadBodyFrame?
    let reliable: Bool
}

enum PadTargetJudge {
    /// Evaluate only the recognised action's extension peak. Interpolate a
    /// bounded, reliable segment across it rather than demanding one tiny-frame
    /// overlap. Every point on that segment uses the same visible circle.
    static func judge(target: PadTargetDefinition, peakMs: Double?, onsetMs: Double, samples: [PadWristSample]) -> PadTargetMatch {
        func uncertain(_ reason: String) -> PadTargetMatch {
            .init(outcome: .uncertain, target: target, closestWrist: nil, peakMs: peakMs, reason: reason)
        }
        guard let peakMs, peakMs >= onsetMs else { return uncertain("missing_recognition_peak") }
        let nearby = samples.filter { $0.tMs >= onsetMs && abs($0.tMs - peakMs) <= 220 }
        var closest: PadPoint?
        var best = Double.infinity
        for (a, b) in zip(nearby, nearby.dropFirst()) {
            guard a.tMs <= peakMs, b.tMs >= peakMs, b.tMs > a.tMs, b.tMs - a.tMs <= 220,
                  a.reliable, b.reliable, let aw = a.wrist, let bw = b.wrist,
                  let ab = a.body, let bb = b.body,
                  target.body.compatible(with: ab, scaleTolerance: 0.35), target.body.compatible(with: bb, scaleTolerance: 0.35),
                  (ab.centre - target.body.centre).length <= target.body.scale * 0.7,
                  (bb.centre - target.body.centre).length <= target.body.scale * 0.7 else { continue }
            let am = PadCameraTransform.metric(aw, aspect: target.body.aspect)
            let bm = PadCameraTransform.metric(bw, aspect: target.body.aspect)
            guard (bm - am).length <= target.body.scale * 2.5 else { continue }
            let centre = PadCameraTransform.metric(target.centre, aspect: target.body.aspect)
            let line = bm - am
            let fraction = line.dot(line) > 0 ? min(1, max(0, (centre - am).dot(line) / line.dot(line))) : 0
            let point = am + line * fraction
            let distance = (point - centre).length
            if distance < best { best = distance; closest = PadCameraTransform.source(point, aspect: target.body.aspect) }
        }
        if closest == nil {
            // Fewer than two bracketing frames survive when the fist points at
            // the camera. One reliable, aligned sample close to the peak is
            // still direct evidence of where the punch landed.
            let centre = PadCameraTransform.metric(target.centre, aspect: target.body.aspect)
            let single = samples.filter { sample in
                guard sample.reliable, sample.wrist != nil, sample.tMs >= onsetMs, abs(sample.tMs - peakMs) <= 150, let body = sample.body else { return false }
                return target.body.compatible(with: body, scaleTolerance: 0.35) && (body.centre - target.body.centre).length <= target.body.scale * 0.7
            }.min { abs($0.tMs - peakMs) < abs($1.tMs - peakMs) }
            if let single, let wrist = single.wrist {
                best = (PadCameraTransform.metric(wrist, aspect: target.body.aspect) - centre).length
                closest = wrist
            }
        }
        guard let closest else { return uncertain(nearby.count < 2 ? "sparse_peak_trajectory" : "unreliable_peak_trajectory_or_alignment") }
        return .init(outcome: best <= target.radius ? .reached : .missed, target: target, closestWrist: closest, peakMs: peakMs, reason: nil)
    }
}

struct PadReachPose: Sendable {
    let tMs: Double
    let points: [PadPoint?]
    let aspect: Double
    var body: PadBodyFrame? { .init(points: points, aspect: aspect) }
}

/// Hands-free timed captures of comfortable projected reach, not technique
/// certification. Each hand gets its own body-relative straight-punch endpoint.
struct PadReachCalibration {
    enum Stage: String { case idle, guardPose, leadReach, leadReturn, rearReach, finalReturn, ready, failed }
    struct Reach { let endpoint: PadPoint; let scatter: Double }
    private(set) var stage: Stage = .idle
    private(set) var notice: String?
    private(set) var calibrationID = UUID()
    private var reference: PadBodyFrame?
    private var guards: [BoxMaxxingJudge.Hand: PadPoint] = [:]
    private var reaches: [BoxMaxxingJudge.Hand: Reach] = [:]
    private var samples: [PadReachPose] = []
    private var stageStarted = 0.0
    private var lastSampleMs = 0.0
    // Hold times for the hands-free capture. Short enough to keep a fighter in
    // stance, long enough to average a steady pose (three or more samples).
    static let guardHoldMs = 700.0
    static let reachHoldMs = 1500.0
    static let reachTimeoutMs = 7000.0
    static let returnHoldMs = 500.0
    /// Shoulder-width units below the shoulder line, with a small safety margin
    /// inside the recognizer's 0.5 straight-punch limit.
    static let headZoneLowerLimit = 0.42
    let stance: BoxMaxxingJudge.Stance
    let hands: [BoxMaxxingJudge.Hand]
    init(stance: BoxMaxxingJudge.Stance, hands: [BoxMaxxingJudge.Hand]) {
        self.stance = stance; self.hands = hands
    }
    var instruction: String {
        switch stage {
        case .idle: notice ?? "Get in your guard to start."
        case .guardPose: "Hold your guard."
        case .leadReach: "Extend your jab and hold."
        case .rearReach: "Extend your cross and hold."
        case .leadReturn, .finalReturn: "Back to guard."
        case .ready: "Locked in. Hit the pads."
        case .failed: notice ?? "Didn’t catch that. Back to guard—we’ll go again."
        }
    }
    mutating func reset(_ message: String? = nil) {
        reference = nil; guards = [:]; reaches = [:]; samples = []; stage = .idle; notice = message; calibrationID = UUID()
    }
    mutating func start(at now: Double) { reset(); transition(.guardPose, at: now) }
    mutating func discardRecentPose() { samples = [] }
    private mutating func transition(_ next: Stage, at now: Double) { stage = next; stageStarted = now; samples = [] }
    func wristIndex(_ hand: BoxMaxxingJudge.Hand) -> Int {
        BoxMaxxingJudge.limbs(hand: hand, stance: stance).first == .left ? 9 : 10
    }
    /// 0…1 through the current timed hold, for a filling progress ring.
    var progress: Double {
        let elapsed = max(0, lastSampleMs - stageStarted)
        switch stage {
        case .guardPose: return min(1, elapsed / Self.guardHoldMs)
        case .leadReach, .rearReach: return min(1, elapsed / Self.reachHoldMs)
        case .leadReturn, .finalReturn: return min(1, elapsed / Self.returnHoldMs)
        case .ready: return 1
        default: return 0
        }
    }
    /// 1-based step of the capture sequence and the number of steps.
    var step: (current: Int, total: Int) {
        let both = hands.count > 1
        switch stage {
        case .guardPose: return (1, both ? 4 : 2)
        case .leadReach: return (2, both ? 4 : 2)
        case .leadReturn: return (3, 4)
        case .rearReach: return (both ? 4 : 2, both ? 4 : 2)
        case .finalReturn, .ready: return (both ? 4 : 2, both ? 4 : 2)
        default: return (0, both ? 4 : 2)
        }
    }
    mutating func observe(_ pose: PadReachPose) {
        lastSampleMs = pose.tMs
        guard let body = pose.body else { return }
        if stage == .ready, let reference, !reference.compatible(with: body) {
            reset("Distance or body angle changed. Recalibrate comfortable reach."); return
        }
        if let last = samples.last, pose.tMs - last.tMs > 250 { samples = [] }
        samples.append(pose); samples.removeAll { pose.tMs - $0.tMs > 750 }
        guard samples.count >= 3, pose.tMs - (samples.first?.tMs ?? pose.tMs) >= 400,
              let mean = average(), let frame = mean.body else { return }
        switch stage {
        case .guardPose:
            guard stable(mean), pose.tMs - stageStarted >= Self.guardHoldMs else { return }
            reference = frame
            for hand in hands { if let wrist = mean.points[wristIndex(hand)] { guards[hand] = frame.local(wrist) } }
            guard guards.count == hands.count else { return }
            transition(hands.contains(.lead) ? .leadReach : .rearReach, at: pose.tMs)
        case .leadReach, .rearReach:
            guard pose.tMs - stageStarted >= Self.reachHoldMs else { return }
            let hand: BoxMaxxingJudge.Hand = stage == .leadReach ? .lead : .rear
            if !stable(mean), pose.tMs - stageStarted < Self.reachTimeoutMs { return }
            guard stable(mean), let reference, let guardPoint = guards[hand], let wrist = mean.points[wristIndex(hand)] else {
                stage = .failed; notice = "Hold the punch out a little steadier. Back to guard—we’ll go again."; return
            }
            let endpoint = reference.local(wrist)
            guard (endpoint - guardPoint).length >= 0.3,
                  abs(frame.scale / reference.scale - 1) <= 0.35,
                  (frame.centre - reference.centre).length < reference.scale * 0.6 else {
                stage = .failed; notice = "Reach a little further, and stay in place. Back to guard—we’ll go again."; return
            }
            let scatter = samples.compactMap { $0.points[wristIndex(hand)] }.map { (reference.local($0) - endpoint).length }.max() ?? 0
            reaches[hand] = Reach(endpoint: endpoint, scatter: scatter)
            transition(hand == .lead && hands.contains(.rear) ? .leadReturn : .finalReturn, at: pose.tMs)
        case .leadReturn, .finalReturn:
            guard isGuard(mean), stable(mean), pose.tMs - stageStarted >= Self.returnHoldMs else { return }
            transition(stage == .leadReturn ? .rearReach : .ready, at: pose.tMs)
        default: break
        }
    }
    private func average() -> PadReachPose? {
        guard let last = samples.last else { return nil }
        let points: [PadPoint?] = (0..<17).map { index in
            let values = samples.compactMap { $0.points[index] }
            guard values.count == samples.count else { return nil }
            return values.reduce(PadPoint(x: 0, y: 0), +) * (1 / Double(values.count))
        }
        return .init(tMs: last.tMs, points: points, aspect: last.aspect)
    }
    private func stable(_ mean: PadReachPose) -> Bool {
        guard let body = mean.body else { return false }
        return samples.allSatisfy { sample in
            guard let frame = sample.body, (frame.centre - body.centre).length < body.scale * 0.12 else { return false }
            return hands.allSatisfy { hand in
                guard let a = sample.points[wristIndex(hand)], let b = mean.points[wristIndex(hand)] else { return false }
                return (body.local(a) - body.local(b)).length < 0.15
            }
        }
    }
    private func isGuard(_ pose: PadReachPose) -> Bool {
        guard let body = pose.body else { return false }
        return hands.allSatisfy { hand in
            guard let point = pose.points[wristIndex(hand)], let expected = guards[hand] else { return false }
            return (body.local(point) - expected).length < 0.4
        }
    }
    func target(id: UUID, hand: BoxMaxxingJudge.Hand, generation: UInt64, level: PadLevel) -> PadTargetDefinition? {
        guard stage == .ready, let pose = average(), stable(pose), isGuard(pose),
              let body = pose.body, let reference, reference.compatible(with: body),
              let reach = reaches[hand], let origin = guards[hand] else { return nil }
        let travel = (reach.endpoint - origin).length
        let base = level == .beginner ? 0.32 : level == .intermediate ? 0.26 : 0.21
        // Calibration noise contributes to the VISIBLE radius, never a hidden
        // judging expansion. Keep guard outside the acceptance circle.
        let localRadius = min(travel * 0.45, max(base, reach.scatter * 2 + 0.08))
        // The recognizer only accepts straight punches whose peak stays above
        // its head-zone line (0.5 shoulder widths below the shoulders). Keep the
        // whole pad inside that zone so hitting the pad is a recognised punch.
        var endpoint = reach.endpoint
        endpoint.y = min(endpoint.y, Self.headZoneLowerLimit - localRadius)
        return .init(cueID: id, calibrationID: calibrationID, generation: generation, hand: hand,
                     centre: body.source(endpoint), origin: body.source(origin), radius: localRadius * body.scale, body: body)
    }
}
