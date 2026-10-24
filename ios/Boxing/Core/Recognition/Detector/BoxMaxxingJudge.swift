import Foundation

// Authorized port of BoxMaxxing 2.1.5 Hermes v98. These are event-judging
// primitives, not an end-to-end detector and not a validated technique score.
// Function IDs and bytecode offsets are recorded beside each recovered operation.
enum BoxMaxxingJudge {
    enum Limb: String, Codable, Sendable { case left, right }
    enum Stance: String, Codable, Sendable { case orthodox, southpaw }
    enum Hand: String, Codable, Sendable { case lead, rear }
    enum PunchKind: String, Codable, Sendable { case straight, hook, uppercut }
    enum Zone: String, Codable, Sendable { case head, body }
    enum Outcome: String, Codable, Sendable {
        case green = "hit_green", yellow = "hit_yellow", early
        case wrongHand = "wrong_hand", timeout = "miss_timeout"
    }
    enum PadState: String, Codable, Sendable {
        case off = "OFF", green = "GREEN", yellow = "YELLOW", fail = "FAIL_RED"
    }
    struct Point: Codable, Equatable, Sendable { var x: Double; var y: Double }
    struct Target: Codable, Equatable, Sendable {
        var xMin: Double; var xMax: Double; var yMin: Double; var yMax: Double
        // #26277 @0x0068c5db: all four boundaries are inclusive.
        func contains(_ point: Point) -> Bool {
            point.x >= xMin && point.x <= xMax && point.y >= yMin && point.y <= yMax
        }
    }
    struct Window: Codable, Equatable, Sendable {
        var tReadyMs: Double
        var earlyGraceMs: Double
        var failMs: Double
        var greenMs: Double
        var yellowMs: Double
    }
    struct Candidate: Codable, Equatable, Sendable {
        var limb: Limb
        var kind: PunchKind
        var zone: Zone
        var confidence: Double
        var tOnsetMs: Double
        var tPeakMs: Double
        var peakWrist: Point
        var direction: String = "forward"
        var vetoes: [String]? = nil
        var classified: Classification? = nil
        var actionId: String? = nil
    }
    struct Classification: Codable, Equatable, Sendable { var cls: String; var p: Double }
    struct Event: Codable, Equatable, Sendable {
        var candidate: Candidate
        var rejected: String? = nil
    }
    struct Result: Codable, Equatable, Sendable {
        var outcome: Outcome
        var reactionMs: Double
        var hitMs: Double
    }
    // Module #4366 @0x004fe104: 120ms early grace; 200ms delayed-result grace.
    // The exact module ID is intentionally not used as an API contract.
    static let defaultEarlyGraceMs: Double = 120
    static let deliveryGraceMs: Double = 200

    // #26273 @0x0068c4d1. Timing uses observed onset and peak, not delivery time.
    static func timing(window: Window, onsetMs: Double, peakMs: Double) -> Outcome {
        let elapsed = peakMs - window.tReadyMs
        if onsetMs < window.tReadyMs - window.earlyGraceMs || elapsed < 0 { return .early }
        if elapsed > window.failMs { return .timeout }
        if elapsed <= window.greenMs { return .green }
        if elapsed <= window.greenMs + window.yellowMs { return .yellow }
        return .timeout
    }
    // #26274 @0x0068c54c. The visual state intentionally does not consult failMs.
    static func padState(window: Window, atMs: Double) -> PadState {
        let elapsed = atMs - window.tReadyMs
        if elapsed < 0 { return .off }
        if elapsed <= window.greenMs { return .green }
        if elapsed <= window.greenMs + window.yellowMs { return .yellow }
        return .fail
    }
    // #26275 @0x0068c598: equality at the deadline is not closed.
    static func windowClosed(_ window: Window, atMs: Double) -> Bool {
        atMs - window.tReadyMs > window.failMs
    }
    // #26276 @0x0068c5b4, literal buffer offset319863 and inline double1.6.
    static func straightTarget(headLineY: Double) -> Target {
        Target(xMin: -1.45, xMax: 1.45, yMin: headLineY - 1.6, yMax: 0.5)
    }
    // #26278 @0x0068c628. Preserve priority: wrong hand precedes timing,
    // early precedes target checks. Wrist overlap never creates a punch event.
    static func punch(_ event: Event, window: Window, expectedLimbs: [Limb], target: Target?) -> Result {
        let candidate = event.candidate
        let reaction = candidate.tOnsetMs - window.tReadyMs
        let hit = candidate.tPeakMs - window.tReadyMs
        guard expectedLimbs.contains(candidate.limb) else {
            return Result(outcome: .wrongHand, reactionMs: reaction, hitMs: hit)
        }
        let outcome = timing(window: window, onsetMs: candidate.tOnsetMs, peakMs: candidate.tPeakMs)
        if outcome == .early { return Result(outcome: outcome, reactionMs: reaction, hitMs: hit) }
        if let target, !target.contains(candidate.peakWrist) {
            return Result(outcome: .timeout, reactionMs: reaction, hitMs: hit)
        }
        return Result(outcome: outcome, reactionMs: reaction, hitMs: hit)
    }
    // #26472 @0x0069246b. Lenient skips kind/head-zone checks only; confidence
    // is still required. Expected punch hand is checked by punch(), separately.
    static func matchesStep(_ event: Event, expectedKind: PunchKind, minimumConfidence: Double, lenient: Bool) -> Bool {
        let candidate = event.candidate
        if lenient { return candidate.confidence >= minimumConfidence }
        return candidate.kind == expectedKind && candidate.zone == .head && candidate.confidence >= minimumConfidence
    }
    // #26481 @0x00692e0b. With no stance or hand, either limb is allowed.
    static func limbs(hand: Hand?, stance: Stance?) -> [Limb] {
        guard let hand, let stance else { return [.left, .right] }
        let lead: Limb = stance == .orthodox ? .left : .right
        return [hand == .lead ? lead : (lead == .left ? .right : .left)]
    }

    struct ClassifierPolicy: Codable, Equatable, Sendable {
        var minP: Double = 0.6
        var decideKind = false
        var acceptDirection = false
        var acceptSize = false
        var acceptConfidence = false
        var vetoNone = false
        var acceptLateralForHook = false
        // #4767 @0x00510409 literal buffers151268/151307. These are bundled
        // policies, not guessed remote overrides or claims of production flags.
        static let bundled = ClassifierPolicy()
        static let armed = ClassifierPolicy(acceptDirection: true, acceptSize: true, acceptConfidence: true, acceptLateralForHook: true)
    }
    // #37421 @0x0080a2af plus #43046 @0x008baac3, exact candidate refinement.
    // Call only after the original geometric detector has emitted a candidate.
    static func apply(_ classification: Classification, to original: Event, policy: ClassifierPolicy, bodyZoneMinY: Double) -> Event {
        var event = original
        event.candidate.classified = classification
        // JS JLess keeps a non-finite value from entering via '<'. Callers must
        // validate inference output at their boundary; no fabricated output here.
        if classification.p < policy.minP { return event }
        let predictedLimb: Limb? = classification.cls.hasSuffix("_left") ? .left : (classification.cls.hasSuffix("_right") ? .right : nil)
        guard predictedLimb == event.candidate.limb else {
            if classification.cls == "none", policy.vetoNone, event.rejected == nil { event.rejected = "classifier" }
            return event
        }
        let kind: PunchKind? = classification.cls.hasPrefix("straight_") ? .straight : (classification.cls.hasPrefix("hook_") ? .hook : (classification.cls.hasPrefix("uppercut_") ? .uppercut : nil))
        if let kind, policy.decideKind { event.candidate.kind = kind }
        guard let kind, let rejected = event.rejected else { return event }
        if rejected == "bilateral" { return event }
        let aboveBodyLine = event.candidate.peakWrist.y <= bodyZoneMinY
        let vetoes = event.candidate.vetoes ?? [rejected]
        let remaining = vetoes.filter { veto in
            let clear = (veto == "vertical" && policy.acceptDirection && aboveBodyLine)
                || (veto == "lateral" && policy.acceptLateralForHook && kind == .hook && aboveBodyLine)
                || ((veto == "too_small" || veto == "too_slow") && policy.acceptSize)
                || (veto == "low_confidence" && policy.acceptConfidence)
            return !clear
        }
        if let first = remaining.first { event.rejected = first; return event }
        if vetoes.contains("vertical") || vetoes.contains("lateral") { event.candidate.direction = "forward" }
        event.rejected = nil
        return event
    }
}
