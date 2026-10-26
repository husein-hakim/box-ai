import Foundation

/// A boxing action the app can ask for and recognise.
/// `side` is the fighter's own left/right (stance-independent); jab/cross are
/// the stance-specific names of the left/right straight.
struct FightAction: Hashable, Codable, Sendable {
    enum Kind: String, Codable, Sendable, CaseIterable { case straight, hook, uppercut, slip, duck }
    enum Side: String, Codable, Sendable { case left, right, none }
    var kind: Kind
    var side: Side

    static func straight(_ side: Side) -> Self { .init(kind: .straight, side: side) }
    static func hook(_ side: Side) -> Self { .init(kind: .hook, side: side) }
    static func uppercut(_ side: Side) -> Self { .init(kind: .uppercut, side: side) }
    static func slip(_ side: Side) -> Self { .init(kind: .slip, side: side) }
    static let duck = Self(kind: .duck, side: .none)

    var isPunch: Bool { kind == .straight || kind == .hook || kind == .uppercut }

    func title(stance: BoxMaxxingJudge.Stance) -> String {
        let lead: Side = stance == .orthodox ? .left : .right
        switch kind {
        case .straight: return side == lead ? String(localized: "Jab") : String(localized: "Cross")
        case .hook: return side == .left ? String(localized: "Left hook") : String(localized: "Right hook")
        case .uppercut: return side == .left ? String(localized: "Left uppercut") : String(localized: "Right uppercut")
        case .slip: return side == .left ? String(localized: "Slip left") : String(localized: "Slip right")
        case .duck: return String(localized: "Duck")
        }
    }
    /// Short HUD label, e.g. "L HOOK".
    func shortTitle(stance: BoxMaxxingJudge.Stance) -> String {
        switch kind {
        case .straight: return title(stance: stance)
        case .hook: return side == .left ? "L Hook" : "R Hook"
        case .uppercut: return side == .left ? "L Upper" : "R Upper"
        case .slip: return side == .left ? "Slip ←" : "Slip →"
        case .duck: return "Duck"
        }
    }
}

/// One recognised action with its peak time (capture clock) and confidence.
struct DetectedMove: Equatable, Sendable {
    enum Source: String, Sendable { case native, kernel }
    var action: FightAction
    var startMs: Double
    var peakMs: Double
    var confidence: Double
    var source: Source
}

/// Native recogniser for hooks, uppercuts, slips and ducks from 2-D pose.
///
/// Works in a body frame built from the shoulders: x along the shoulder line
/// toward the fighter's LEFT, y down, both in shoulder widths. This makes every
/// rule independent of camera mirroring, distance and stance. Joint positions
/// are One-Euro smoothed; dodges are measured against a rolling guard baseline
/// that only adapts while the fighter is still.
struct MoveRecognizer {
    struct Frame {
        let tMs: Double
        /// 17 COCO keypoints in normalised, unmirrored image coordinates; nil when not confidently observed.
        let points: [PadPoint?]
        let aspect: Double
    }
    struct Tuning: Sendable {
        var windowMs = 600.0
        // Hook: elbow lifted to shoulder height, fist sweeps across toward the midline.
        var hookElbowMaxY = 0.25
        var hookWristMinY = -1.2, hookWristMaxY = 0.45
        var hookMinSweep = 0.45
        var hookMaxRise = 0.45
        var hookForearmMaxTilt = 0.5
        var hookMaxDurationMs = 480.0
        // Uppercut: fist rises from below the shoulder line with the elbow under it.
        var upperMinRise = 0.5
        var upperStartMinY = 0.0
        var upperEndMaxY = 0.1
        var upperElbowBelowWrist = 0.25
        var upperMaxLateral = 0.55
        var upperMaxDurationMs = 480.0
        // Dodges, in baseline shoulder widths.
        var slipMinHead = 0.38
        var slipMinLean = 0.12
        var slipMinTiltDegrees = 6.0
        var duckMinHead = 0.45
        var duckMinShoulders = 0.3
        var dodgeMaxDurationMs = 650.0
        var refractoryMs = 320.0
        var dodgeRefractoryMs = 650.0
    }

    private struct Local { var tMs: Double; var elbow: [FightAction.Side: PadPoint?]; var wrist: [FightAction.Side: PadPoint?]; var head: PadPoint?; var shoulderMid: PadPoint; var scale: Double; var axis: PadPoint }
    private struct Baseline { var head: PadPoint?; var shoulderMid: PadPoint; var scale: Double; var axis: PadPoint }

    var tuning = Tuning()
    private var filters: [BoxMaxxingOneEuro] = Array(repeating: BoxMaxxingOneEuro(configuration: .init(minCutoffHz: 3, beta: 4, dCutoffHz: 2)), count: 34)
    private var history: [Local] = []
    private var baseline: Baseline?
    private var quietSinceMs: Double?
    private var lastEmit: [FightAction: Double] = [:]
    private var dodgeArmed = true
    private var lastMs: Double?

    mutating func reset() {
        for i in filters.indices { filters[i].reset() }
        history = []; baseline = nil; quietSinceMs = nil; lastEmit = [:]; dodgeArmed = true; lastMs = nil
    }

    /// Feed one frame; returns any actions whose peak was just reached.
    mutating func push(_ frame: Frame) -> [DetectedMove] {
        guard frame.points.count == 17, frame.aspect > 0 else { return [] }
        let dtS = max(0.005, min(0.25, (frame.tMs - (lastMs ?? frame.tMs - 40)) / 1000))
        lastMs = frame.tMs
        // Smooth in metric space (x scaled by aspect) so distances are isotropic.
        var metric: [PadPoint?] = Array(repeating: nil, count: 17)
        for i in 0..<17 {
            guard let p = frame.points[i] else { filters[i * 2].reset(); filters[i * 2 + 1].reset(); continue }
            let m = PadCameraTransform.metric(p, aspect: frame.aspect)
            metric[i] = .init(x: filters[i * 2].filter(m.x, dtS: dtS), y: filters[i * 2 + 1].filter(m.y, dtS: dtS))
        }
        guard let left = metric[5], let right = metric[6] else { history.removeAll(); quietSinceMs = nil; return [] }
        let width = (left - right).length
        guard width > 0.02 else { return [] }
        let axis = (left - right) * (1 / width)          // toward the fighter's left
        let down = PadPoint(x: -axis.y, y: axis.x).y >= 0 ? PadPoint(x: -axis.y, y: axis.x) : PadPoint(x: axis.y, y: -axis.x)
        let mid = (left + right) * 0.5
        func local(_ p: PadPoint?) -> PadPoint? {
            guard let p else { return nil }
            let d = p - mid
            return .init(x: d.dot(axis) / width, y: d.dot(down) / width)
        }
        let head = metric[0] ?? average([metric[1], metric[2]])
        let entry = Local(tMs: frame.tMs,
                          elbow: [.left: local(metric[7]), .right: local(metric[8])],
                          wrist: [.left: local(metric[9]), .right: local(metric[10])],
                          head: head, shoulderMid: mid, scale: width, axis: axis)
        history.append(entry)
        history.removeAll { frame.tMs - $0.tMs > tuning.windowMs }
        updateBaseline(now: entry)

        var found: [DetectedMove] = []
        for side in [FightAction.Side.left, .right] {
            if let move = detectHook(side: side) { found.append(move) }
            else if let move = detectUppercut(side: side) { found.append(move) }
        }
        if let move = detectDodge(now: entry) { found.append(move) }
        return found.filter { move in
            let gap = move.action.isPunch ? tuning.refractoryMs : tuning.dodgeRefractoryMs
            if let last = lastEmit[move.action], move.peakMs - last < gap { return false }
            lastEmit[move.action] = move.peakMs
            return true
        }
    }

    /// True while this arm looks part-way through a hook (elbow high, fist sweeping
    /// inward) or an uppercut (fist rising from below the shoulders). Lets fusion hold
    /// a kernel "straight" that is really the wind-up of a more specific punch.
    func specificInProgress(side: FightAction.Side) -> Bool {
        guard let last = history.last, let w = last.wrist[side] ?? nil, let e = last.elbow[side] ?? nil else { return false }
        let outward = side == .left ? 1.0 : -1.0
        let recent = history.filter { last.tMs - $0.tMs <= 220 }.compactMap { $0.wrist[side] ?? nil }
        guard let first = recent.first else { return false }
        let inward = (first.x - w.x) * outward
        if e.y <= tuning.hookElbowMaxY + 0.1, inward >= 0.12, (tuning.hookWristMinY...tuning.hookWristMaxY).contains(w.y) { return true }
        let lowest = history.filter { last.tMs - $0.tMs <= 320 }.compactMap { ($0.wrist[side] ?? nil)?.y }.max() ?? w.y
        if lowest >= tuning.upperStartMinY, first.y - w.y >= 0.15 { return true }
        return false
    }

    // MARK: Punches

    private func detectHook(side: FightAction.Side) -> DetectedMove? {
        let outward = side == .left ? 1.0 : -1.0
        let samples = history.compactMap { e -> (t: Double, w: PadPoint, e: PadPoint)? in
            guard let w = e.wrist[side] ?? nil, let el = e.elbow[side] ?? nil else { return nil }
            return (e.tMs, w, el)
        }
        guard samples.count >= 4, let last = samples.last else { return nil }
        // Peak = now, and the fist has started to slow (or reverse) its inward sweep.
        let prev = samples[samples.count - 2]
        let inwardNow = (prev.w.x - last.w.x) * outward
        guard let outer = samples.dropLast().max(by: { $0.w.x * outward < $1.w.x * outward }),
              last.t - outer.t <= tuning.hookMaxDurationMs, last.t > outer.t else { return nil }
        let sweep = (outer.w.x - last.w.x) * outward
        guard sweep >= tuning.hookMinSweep else { return nil }
        let segment = samples.filter { $0.t >= outer.t }
        let speeds = zip(segment, segment.dropFirst()).map { ($0.w.x - $1.w.x) * outward / max(1, $1.t - $0.t) }
        guard let maxSpeed = speeds.max(), maxSpeed > 0, inwardNow / max(1, last.t - prev.t) <= maxSpeed * 0.45 else { return nil }
        // Elbow high and forearm level for most of the sweep; fist at head height; little vertical travel.
        let high = segment.filter { $0.e.y <= tuning.hookElbowMaxY }.count
        guard Double(high) >= Double(segment.count) * 0.6,
              (tuning.hookWristMinY...tuning.hookWristMaxY).contains(last.w.y),
              abs(last.w.y - outer.w.y) <= tuning.hookMaxRise,
              abs(last.w.y - last.e.y) <= tuning.hookForearmMaxTilt else { return nil }
        let confidence = min(1, 0.55 + 0.45 * min(1, (sweep - tuning.hookMinSweep) / tuning.hookMinSweep + Double(high) / Double(segment.count) - 0.6))
        return .init(action: .hook(side), startMs: outer.t, peakMs: last.t, confidence: confidence, source: .native)
    }

    private func detectUppercut(side: FightAction.Side) -> DetectedMove? {
        let samples = history.compactMap { e -> (t: Double, w: PadPoint, e: PadPoint)? in
            guard let w = e.wrist[side] ?? nil, let el = e.elbow[side] ?? nil else { return nil }
            return (e.tMs, w, el)
        }
        guard samples.count >= 4, let last = samples.last else { return nil }
        let prev = samples[samples.count - 2]
        guard let low = samples.dropLast().max(by: { $0.w.y < $1.w.y }), last.t > low.t,
              last.t - low.t <= tuning.upperMaxDurationMs else { return nil }
        let rise = low.w.y - last.w.y
        guard rise >= tuning.upperMinRise, low.w.y >= tuning.upperStartMinY, last.w.y <= tuning.upperEndMaxY,
              abs(last.w.x - low.w.x) <= tuning.upperMaxLateral,
              last.e.y - last.w.y >= tuning.upperElbowBelowWrist else { return nil }
        let segment = samples.filter { $0.t >= low.t }
        let speeds = zip(segment, segment.dropFirst()).map { ($0.w.y - $1.w.y) / max(1, $1.t - $0.t) }
        let upNow = (prev.w.y - last.w.y) / max(1, last.t - prev.t)
        guard let maxSpeed = speeds.max(), maxSpeed > 0, upNow <= maxSpeed * 0.45 else { return nil }
        let confidence = min(1, 0.55 + 0.45 * min(1, (rise - tuning.upperMinRise) / tuning.upperMinRise + 0.3))
        return .init(action: .uppercut(side), startMs: low.t, peakMs: last.t, confidence: confidence, source: .native)
    }

    // MARK: Dodges

    private mutating func updateBaseline(now: Local) {
        // "Quiet" = head, shoulders and both fists nearly still for 300 ms.
        let recent = history.filter { now.tMs - $0.tMs <= 200 }
        guard let first = recent.first, now.tMs - first.tMs >= 120 else { return }
        let dt = (now.tMs - first.tMs) / 1000
        let shoulderSpeed = (now.shoulderMid - first.shoulderMid).length / now.scale / dt
        let headSpeed = zip([first.head], [now.head]).compactMap { a, b -> Double? in guard let a, let b else { return nil }; return (b - a).length / now.scale / dt }.first ?? 0
        let wristSpeed = [FightAction.Side.left, .right].compactMap { s -> Double? in
            guard let a = first.wrist[s] ?? nil, let b = now.wrist[s] ?? nil else { return nil }
            return (b - a).length / dt
        }.max() ?? 0
        let quiet = shoulderSpeed < 0.6 && headSpeed < 0.8 && wristSpeed < 1.6
        if quiet { quietSinceMs = quietSinceMs ?? now.tMs } else { quietSinceMs = nil }
        guard quiet, let since = quietSinceMs, now.tMs - since >= 300 else { return }
        if var base = baseline {
            // Re-arm dodges once back near the guard baseline.
            let alpha = 0.08
            base.shoulderMid = base.shoulderMid * (1 - alpha) + now.shoulderMid * alpha
            base.scale = base.scale * (1 - alpha) + now.scale * alpha
            if let h = now.head { base.head = (base.head ?? h) * (1 - alpha) + h * alpha }
            base.axis = now.axis
            baseline = base
        } else {
            baseline = .init(head: now.head, shoulderMid: now.shoulderMid, scale: now.scale, axis: now.axis)
        }
    }

    private mutating func detectDodge(now: Local) -> DetectedMove? {
        guard let base = baseline else { return nil }
        let baseDown = PadPoint(x: -base.axis.y, y: base.axis.x).y >= 0 ? PadPoint(x: -base.axis.y, y: base.axis.x) : PadPoint(x: base.axis.y, y: -base.axis.x)
        func offset(_ p: PadPoint?, _ b: PadPoint?) -> PadPoint? {
            guard let p, let b else { return nil }
            let d = p - b
            return .init(x: d.dot(base.axis) / base.scale, y: d.dot(baseDown) / base.scale)
        }
        struct Pose { let t: Double; let head: PadPoint; let shoulders: PadPoint; let scale: Double; let tilt: Double
            var magnitude: Double { max(abs(head.x), head.y) } }
        let poses: [Pose] = history.compactMap { e in
            guard let shoulders = offset(e.shoulderMid, base.shoulderMid) else { return nil }
            let tilt = asin(max(-1, min(1, e.axis.x * base.axis.y - e.axis.y * base.axis.x))) * 180 / .pi
            return Pose(t: e.tMs, head: offset(e.head, base.head) ?? shoulders, shoulders: shoulders, scale: e.scale / base.scale, tilt: tilt)
        }
        guard let current = poses.last else { return nil }
        if !dodgeArmed {
            if current.magnitude < 0.2 { dodgeArmed = true }
            return nil
        }
        // The peak of the recent movement, judged once the fighter starts back or
        // holds it for 120 ms. It must rise quickly from a quiet guard.
        guard let peakIndex = poses.indices.max(by: { poses[$0].magnitude < poses[$1].magnitude }) else { return nil }
        let peak = poses[peakIndex]
        let returning = current.magnitude < peak.magnitude - 0.05
        let held = current.t - peak.t >= 120 && current.magnitude >= peak.magnitude - 0.05
        guard returning || held,
              let start = poses[...peakIndex].last(where: { $0.magnitude < 0.15 }),
              peak.t - start.t <= tuning.dodgeMaxDurationMs else { return nil }

        let lean = abs(peak.head.x) - abs(peak.shoulders.x)
        if abs(peak.head.x) >= tuning.slipMinHead, abs(peak.head.y) <= 0.6, (0.8...1.25).contains(peak.scale),
           lean >= tuning.slipMinLean || abs(peak.tilt) >= tuning.slipMinTiltDegrees {
            dodgeArmed = false
            let side: FightAction.Side = peak.head.x > 0 ? .left : .right
            return .init(action: .slip(side), startMs: start.t, peakMs: peak.t,
                         confidence: min(1, 0.6 + 0.4 * (abs(peak.head.x) - tuning.slipMinHead) / tuning.slipMinHead), source: .native)
        }
        if peak.head.y >= tuning.duckMinHead, peak.shoulders.y >= tuning.duckMinShoulders, abs(peak.head.x) <= 0.45, (0.85...1.4).contains(peak.scale) {
            dodgeArmed = false
            return .init(action: .duck, startMs: start.t, peakMs: peak.t,
                         confidence: min(1, 0.6 + 0.4 * (peak.head.y - tuning.duckMinHead) / tuning.duckMinHead), source: .native)
        }
        // A large, fast movement that is neither: disarm so it is not re-judged.
        if returning && peak.magnitude >= 0.35 { dodgeArmed = false }
        return nil
    }

    private func average(_ points: [PadPoint?]) -> PadPoint? {
        let present = points.compactMap { $0 }
        guard !present.isEmpty else { return nil }
        return present.reduce(PadPoint(x: 0, y: 0), +) * (1 / Double(present.count))
    }
}

/// Merges the recovered kernel's punch candidates with native detections.
///
/// The kernel is the validated source for straights. It sometimes reports a
/// "straight" a moment before recognising the same motion as a hook or uppercut,
/// so straights are held for `settleMs` and dropped if a more specific punch with
/// the same hand arrives. Duplicates of one action within `mergeMs` collapse.
struct MoveFusion {
    var settleMs = 150.0
    var maxHoldMs = 450.0
    var mergeMs = 300.0
    private var pendingStraights: [DetectedMove] = []
    private var emitted: [DetectedMove] = []

    mutating func reset() { pendingStraights = []; emitted = [] }

    mutating func push(native: [DetectedMove], kernel: [BoxMaxxingJudge.Event], nowMs: Double,
                       busy: (FightAction.Side) -> Bool = { _ in false }) -> [DetectedMove] {
        var out: [DetectedMove] = []
        func emit(_ move: DetectedMove) {
            if emitted.contains(where: { $0.action == move.action && abs($0.peakMs - move.peakMs) < mergeMs }) { return }
            emitted.append(move); out.append(move)
        }
        var specific = native.filter { $0.action.kind == .hook || $0.action.kind == .uppercut }
        for event in kernel where event.rejected == nil {
            let c = event.candidate
            let side: FightAction.Side = c.limb == .left ? .left : .right
            switch c.kind {
            case .straight:
                pendingStraights.append(.init(action: .straight(side), startMs: c.tOnsetMs, peakMs: c.tPeakMs, confidence: c.confidence, source: .kernel))
            case .hook:
                specific.append(.init(action: .hook(side), startMs: c.tOnsetMs, peakMs: c.tPeakMs, confidence: c.confidence * 0.9, source: .kernel))
            case .uppercut:
                specific.append(.init(action: .uppercut(side), startMs: c.tOnsetMs, peakMs: c.tPeakMs, confidence: c.confidence * 0.9, source: .kernel))
            }
        }
        // A specific punch claims its hand: cancel overlapping straights.
        for move in specific {
            pendingStraights.removeAll { $0.action.side == move.action.side && abs($0.peakMs - move.peakMs) <= mergeMs }
            emit(move)
        }
        for move in native where move.action.kind == .slip || move.action.kind == .duck { emit(move) }
        // Release straights that have settled without a competing specific punch.
        func settled(_ move: DetectedMove) -> Bool {
            let age = nowMs - move.peakMs
            return age >= maxHoldMs || (age >= settleMs && !busy(move.action.side))
        }
        let ready = pendingStraights.filter(settled)
        pendingStraights.removeAll(where: settled)
        for move in ready {
            if emitted.contains(where: { $0.action.side == move.action.side && ($0.action.kind == .hook || $0.action.kind == .uppercut) && abs($0.peakMs - move.peakMs) <= mergeMs }) { continue }
            emit(move)
        }
        emitted.removeAll { nowMs - $0.peakMs > 2000 }
        return out
    }
}
