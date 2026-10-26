import Foundation

/// One pose sample from a video file: 17 COCO keypoints in normalised upright
/// image coordinates (nil when not confidently seen).
struct PoseSample: Sendable {
    var tMs: Double
    var points: [PadPoint?]
    var aspect: Double
}

/// What the on-device pass measured over a clip. Runs locally and costs nothing;
/// the AI review receives it as evidence alongside a few key images.
struct ClipMotion: Codable, Equatable, Sendable {
    struct Move: Codable, Equatable, Sendable {
        var seconds: Double
        var action: FightAction
        var confidence: Double
        /// The other hand had dropped past mid-torso at the punch's peak.
        var otherHandLow: Bool
        /// The punching hand fell to about belt height on the way back.
        var droppedAfter: Bool
    }
    var durationSeconds: Double
    /// Share of samples where the boxer's upper body was clearly tracked.
    var trackedShare: Double
    /// Share of samples with both ankles visible.
    var feetVisibleShare: Double
    var moves: [Move]
    /// Share of tracked, non-punching time with both hands in guard (above mid-torso).
    var guardShare: Double?
    /// Average ankle spread in shoulder widths when the feet are visible.
    var stanceWidth: Double?
    /// Hip travel across the frame, shoulder widths per second (footwork activity).
    var footworkRate: Double?
    /// Typical sideways head offset from the hips, shoulder widths (head movement).
    var headMovement: Double?

    var punches: [Move] { moves.filter { $0.action.isPunch } }
    var defenses: [Move] { moves.filter { !$0.action.isPunch } }
    var trackedSeconds: Double { durationSeconds * trackedShare }
    var punchesPerMinute: Double? { trackedSeconds >= 5 ? Double(punches.count) / trackedSeconds * 60 : nil }
    /// Groups of moves no more than 0.7 s apart.
    var combinations: [[Move]] {
        var groups: [[Move]] = []
        for move in moves.sorted(by: { $0.seconds < $1.seconds }) {
            if let last = groups.last?.last, move.seconds - last.seconds <= 0.7 { groups[groups.count - 1].append(move) }
            else { groups.append([move]) }
        }
        return groups
    }
    var otherHandLowShare: Double? { punches.isEmpty ? nil : Double(punches.filter(\.otherHandLow).count) / Double(punches.count) }
    var droppedAfterShare: Double? { punches.isEmpty ? nil : Double(punches.filter(\.droppedAfter).count) / Double(punches.count) }
    var isUsable: Bool { trackedShare >= 0.3 }

    func counts(stance: BoxMaxxingJudge.Stance) -> [(String, Int)] {
        Dictionary(grouping: moves, by: { $0.action.title(stance: stance) }).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
    }

    /// Plain-text evidence for the AI. Numbers are labelled as camera estimates.
    func evidence(stance: BoxMaxxingJudge.Stance, offsetSeconds: Double) -> String {
        guard isUsable else {
            return "On-device tracking: the boxer was clearly tracked in only \(Int(trackedShare * 100))% of the clip, so no movement statistics are available. Judge from the images alone."
        }
        func pct(_ v: Double?) -> String { v.map { "\(Int(($0 * 100).rounded()))%" } ?? "not measurable" }
        func num(_ v: Double?, _ digits: Int = 1) -> String { v.map { String(format: "%.\(digits)f", $0) } ?? "not measurable" }
        let combos = combinations.filter { $0.count >= 2 }
        let longest = combinations.map(\.count).max() ?? 0
        var lines = [
            "On-device pose tracking (single camera, 2-D, estimates only; it can miss or misread moves):",
            "- Tracked \(Int(trackedShare * 100))% of \(num(durationSeconds)) s. Feet visible \(pct(feetVisibleShare)).",
            "- Moves recognised: \(moves.isEmpty ? "none" : counts(stance: stance).map { "\($0.0) ×\($0.1)" }.joined(separator: ", ")).",
            "- Punch rate: \(punchesPerMinute.map { "\(Int($0.rounded())) per minute" } ?? "not measurable"). Combinations of 2+: \(combos.count); longest \(longest).",
            "- Both hands in guard (above mid-torso) between punches: \(pct(guardShare)).",
            "- Other hand dropped past mid-torso at a punch's peak: \(pct(otherHandLowShare)). Punching hand fell to belt height on the return: \(pct(droppedAfterShare)).",
            "- Head movement (sideways offset from hips): \(num(headMovement, 2)) shoulder widths. Dodges recognised: \(defenses.count).",
            "- Footwork activity: \(num(footworkRate, 2)) shoulder widths/s. Stance width: \(num(stanceWidth)) shoulder widths."
        ]
        if !moves.isEmpty {
            lines.append("- Timeline: " + moves.prefix(40).map { move in
                var flags: [String] = []
                if move.otherHandLow { flags.append("other hand low") }
                if move.droppedAfter { flags.append("dropped on return") }
                return String(format: "%.1fs ", move.seconds + offsetSeconds) + move.action.title(stance: stance) + (flags.isEmpty ? "" : " (" + flags.joined(separator: ", ") + ")")
            }.joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Turns pose samples into recognised moves and simple guard/footwork measures,
/// using the same recovered kernel + native recogniser + fusion as live sparring.
enum ClipMotionAnalyzer {
    static func analyze(_ samples: [PoseSample], stance: BoxMaxxingJudge.Stance) throws -> ClipMotion {
        guard let first = samples.first, let last = samples.last else {
            return ClipMotion(durationSeconds: 0, trackedShare: 0, feetVisibleShare: 0, moves: [])
        }
        let kernel = try BoxMaxxingKernel()
        try kernel.setStance(stance)
        var recognizer = MoveRecognizer(), fusion = MoveFusion()
        var detected: [DetectedMove] = []
        var tracked = 0, feet = 0
        var bodies: [Double: Body] = [:]
        for sample in samples {
            let body = Body(sample)
            if let body { tracked += 1; bodies[sample.tMs] = body; if body.feetVisible { feet += 1 } }
            let keypoints: [[String: Any]] = sample.points.map { p in p.map { ["x": $0.x, "y": $0.y, "score": 0.9] } ?? ["x": 0, "y": 0, "score": 0] }
            let height = 480.0
            let frame: [String: Any] = ["tMs": sample.tMs, "width": height * sample.aspect, "height": height, "keypoints": keypoints]
            let kernelSample = try? kernel.pushJSON(JSONSerialization.data(withJSONObject: frame))
            let native = recognizer.push(.init(tMs: sample.tMs, points: sample.points, aspect: sample.aspect))
            let current = recognizer
            detected += fusion.push(native: native, kernel: kernelSample?.punches ?? [], nowMs: sample.tMs, busy: { current.specificInProgress(side: $0) })
        }
        // Flush straights still waiting to settle.
        detected += fusion.push(native: [], kernel: [], nowMs: last.tMs + 1000)

        let times = bodies.keys.sorted()
        func body(near t: Double) -> Body? {
            guard let nearest = times.min(by: { abs($0 - t) < abs($1 - t) }), abs(nearest - t) <= 120 else { return nil }
            return bodies[nearest]
        }
        let moves: [ClipMotion.Move] = detected.sorted { $0.peakMs < $1.peakMs }.map { move in
            var otherLow = false, dropped = false
            if move.action.isPunch, move.action.side != .none {
                let other: FightAction.Side = move.action.side == .left ? .right : .left
                otherLow = body(near: move.peakMs)?.handLow(other, below: 0.6) ?? false
                dropped = times.filter { $0 > move.peakMs && $0 <= move.peakMs + 500 }.contains { bodies[$0]?.handLow(move.action.side, below: 0.85) ?? false }
            }
            return .init(seconds: (move.peakMs - first.tMs) / 1000, action: move.action, confidence: move.confidence, otherHandLow: otherLow, droppedAfter: dropped)
        }
        // Guard: exclude half a second around every punch.
        let punchTimes = detected.filter { $0.action.isPunch }.map(\.peakMs)
        let calm = times.filter { t in !punchTimes.contains { abs($0 - t) < 500 } }
        let guardShare = calm.count >= 10 ? Double(calm.filter { !bodies[$0]!.handLow(.left, below: 0.6) && !bodies[$0]!.handLow(.right, below: 0.6) }.count) / Double(calm.count) : nil
        let widths = times.compactMap { bodies[$0]?.stanceWidth }
        let heads = times.compactMap { bodies[$0]?.headOffset }
        var travel = 0.0, travelTime = 0.0
        for (a, b) in zip(times, times.dropFirst()) where b - a <= 250 {
            guard let p = bodies[a], let q = bodies[b] else { continue }
            travel += abs(q.hipX - p.hipX) / ((p.scale + q.scale) / 2); travelTime += (b - a) / 1000
        }
        let count = Double(samples.count)
        return ClipMotion(
            durationSeconds: max(0, (last.tMs - first.tMs) / 1000),
            trackedShare: Double(tracked) / count,
            feetVisibleShare: Double(feet) / count,
            moves: moves,
            guardShare: guardShare,
            stanceWidth: widths.count >= 10 ? widths.reduce(0, +) / Double(widths.count) : nil,
            footworkRate: travelTime >= 3 ? travel / travelTime : nil,
            headMovement: heads.count >= 10 ? standardDeviation(heads) : nil)
    }

    /// Times worth showing the AI: recognised moves (faults first, varied kinds),
    /// then evenly spaced fill so the whole segment is covered.
    static func keyMoments(_ motion: ClipMotion, duration: Double, count: Int) -> [Double] {
        guard duration > 0, count > 0 else { return [] }
        var picked: [Double] = []
        func add(_ t: Double) {
            let t = min(max(t, 0.3), max(0.3, duration - 0.35))
            if !picked.contains(where: { abs($0 - t) < max(0.8, duration / Double(count * 3)) }) { picked.append(t) }
        }
        let faults = motion.punches.filter { $0.otherHandLow || $0.droppedAfter }
        var seenKinds: Set<FightAction> = []
        for move in faults.prefix(2) { add(move.seconds) }
        for move in motion.moves where !seenKinds.contains(move.action) && picked.count < count - 1 { seenKinds.insert(move.action); add(move.seconds) }
        var i = 0
        while picked.count < count && i < count * 4 {
            add(duration * (Double(i % count) + 0.5) / Double(count) + Double(i / count) * 0.37)
            i += 1
        }
        return Array(picked.prefix(count)).sorted()
    }

    private static func standardDeviation(_ values: [Double]) -> Double {
        let mean = values.reduce(0, +) / Double(values.count)
        return (values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)).squareRoot()
    }

    /// Body-frame geometry for one sample: shoulder-width units, y down.
    private struct Body {
        let scale: Double
        let shoulderY: Double
        /// Shoulder line to hip line, or an estimate from shoulder width when hips are hidden.
        let torso: Double
        let wrists: [FightAction.Side: PadPoint]
        let hipX: Double
        let headOffset: Double?
        let stanceWidth: Double?
        var feetVisible: Bool { stanceWidth != nil }
        init?(_ s: PoseSample) {
            func p(_ i: Int) -> PadPoint? { s.points.indices.contains(i) ? s.points[i].map { PadPoint(x: $0.x * s.aspect, y: $0.y) } : nil }
            guard let ls = p(5), let rs = p(6) else { return nil }
            let scale = ((ls.x - rs.x) * (ls.x - rs.x) + (ls.y - rs.y) * (ls.y - rs.y)).squareRoot()
            guard scale > 0.02 else { return nil }
            let visible = s.points.compactMap { $0 }.count
            guard visible >= 8 else { return nil }
            self.scale = scale
            shoulderY = (ls.y + rs.y) / 2
            var wrists: [FightAction.Side: PadPoint] = [:]
            if let l = p(9) { wrists[.left] = l }
            if let r = p(10) { wrists[.right] = r }
            self.wrists = wrists
            let lh = p(11), rh = p(12)
            let hipY = (lh != nil && rh != nil) ? (lh!.y + rh!.y) / 2 : nil
            torso = hipY.map { max($0 - (ls.y + rs.y) / 2, scale * 0.8) } ?? scale * 1.3
            let hip = (lh != nil && rh != nil) ? (lh!.x + rh!.x) / 2 : (ls.x + rs.x) / 2
            hipX = hip
            headOffset = p(0).map { ($0.x - hip) / scale }
            if let la = p(15), let ra = p(16) { stanceWidth = abs(la.x - ra.x) / scale } else { stanceWidth = nil }
        }
        /// Wrist lower than `below` of the way from the shoulder line to the hips.
        /// A normal guard keeps the wrists around the upper chest (about 0.3–0.45).
        func handLow(_ side: FightAction.Side, below: Double) -> Bool {
            guard let w = wrists[side] else { return false }
            return (w.y - shoulderY) / torso > below
        }
    }
}
