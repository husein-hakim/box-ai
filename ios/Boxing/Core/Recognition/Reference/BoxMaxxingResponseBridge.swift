import Foundation

/// Native lifecycle boundary around the recovered StepJudge. Queue-confined with
/// its recognition kernel; product policy/timings are supplied, never invented here.
/// A render acknowledgement is required for every cue, including after a pause.
final class BoxMaxxingResponseBridge {
    struct Step: Codable, Equatable, Sendable {
        var id: String
        var hand: BoxMaxxingJudge.Hand
        var targetReps: Int
        var timeoutMs: Double
        var minConfidence: Double
    }
    struct CueToken: Equatable, Sendable {
        let id: UUID
        let stepID: String
        let generation: UInt64
    }
    struct Event: Codable, Equatable, Sendable {
        let kind: String
        var tMs: Double?
        var stepId: String?
        var actionId: String?
        var cueId: String?
        var reason: String?
        var grade: String?
        var outcome: String?
        var reactionMs: Double?
        var latencyMs: Double?
        var reps: Int?
        var targetReps: Int?
    }
    struct Summary: Codable, Equatable, Sendable {
        let steps: Int
        let completed: Int
        let timedOut: Int
        let aborted: Int
        let reps: Int
        let wrongHand: Int
        let wrongKind: Int
        let missed: Int
        let reactionMedianMs: Double?
        let reactionBestMs: Double?
        let cadenceMedianMs: Double?
        let formFlags: Int
    }
    enum ObservationResult: Equatable {
        case ignored
        case timingUncertain
        case judged([Event])
    }
    enum Failure: Error { case invalidContract }
    private struct Active {
        var step: Step
        var token: CueToken
        var openedMs: Double
        var readyMs: Double?
        var lastCaptureMs: Double?
        var reliableOnsetAfterMs: Double?
    }
    private let kernel: BoxMaxxingKernel
    private var active: Active?

    init(kernel: BoxMaxxingKernel) { self.kernel = kernel }

    /// Only jab/cross descriptors are exposed. Other recovered detectors remain
    /// diagnostics until their individual validation and screen integration.
    func open(_ step: Step, atMs: Double, generation: UInt64) throws -> (CueToken, [Event]) {
        guard atMs.isFinite, !step.id.isEmpty, (1...1000).contains(step.targetReps),
              step.timeoutMs.isFinite, step.timeoutMs > 0,
              step.minConfidence.isFinite, (0...1).contains(step.minConfidence) else { throw Failure.invalidContract }
        let token = CueToken(id: UUID(), stepID: step.id, generation: generation)
        let descriptor: [String: Any] = ["id": step.id, "class": "reactive", "detector": "straight",
            "hand": step.hand.rawValue, "zone": "head", "framing": "upper", "targetReps": step.targetReps,
            "timeoutMs": step.timeoutMs, "minConfidence": step.minConfidence]
        let context: [String: Any] = ["stepId": step.id, "descriptor": descriptor, "cueDriven": true]
        let events: [Event] = try call("open", [context, atMs])
        active = Active(step: step, token: token, openedMs: atMs)
        return (token, events)
    }

    /// Call from the renderer's presentation acknowledgement, not its cue request.
    /// Stale/duplicate acknowledgements cannot move the response clock.
    @discardableResult
    func presented(_ token: CueToken, window: BoxMaxxingJudge.Window) throws -> Bool {
        guard var current = active, current.token == token, current.readyMs == nil else { return false }
        guard window.tReadyMs.isFinite, window.tReadyMs >= current.openedMs,
              [window.earlyGraceMs, window.failMs, window.greenMs, window.yellowMs].allSatisfy({ $0.isFinite && $0 >= 0 }),
              window.failMs > 0 else { throw Failure.invalidContract }
        let cue: [String: Any] = ["stepId": current.step.id, "id": token.id.uuidString,
            "detector": "straight", "hand": current.step.hand.rawValue, "zone": "head"]
        let payload: [String: Any] = ["cue": cue, "tReadyMs": window.tReadyMs, "earlyGraceMs": window.earlyGraceMs,
            "failMs": window.failMs, "greenMs": window.greenMs, "yellowMs": window.yellowMs]
        _ = try raw("padReady", [payload])
        current.readyMs = window.tReadyMs; active = current
        return true
    }

    /// A skipped observation is never judged, and a later candidate spanning
    /// that gap must not be credited using stale/held evidence.
    func excludeActionsThrough(atMs: Double) {
        guard atMs.isFinite, var current = active else { return }
        current.reliableOnsetAfterMs = max(current.reliableOnsetAfterMs ?? current.openedMs, atMs)
        active = current
    }

    func observe(_ sample: BoxMaxxingKernel.Sample, captureMs: Double, deliveredMs: Double,
                 generation: UInt64, timingReliable: Bool, upperBodyObserved: Bool = false) throws -> ObservationResult {
        guard var current = active, current.readyMs != nil, generation == current.token.generation,
              captureMs.isFinite, deliveredMs.isFinite, deliveredMs >= captureMs,
              abs(sample.frame.tMs - captureMs) <= 0.001,
              captureMs >= current.openedMs,
              current.lastCaptureMs.map({ captureMs > $0 }) ?? true else { return .ignored }
        guard timingReliable else {
            try suspend(atMs: deliveredMs)
            return .timingUncertain
        }
        // The raw judge can accept a resubmitted pre-pause event after resume.
        // Generation + capture ordering + onset floor close that native boundary.
        guard var frame = try JSONSerialization.jsonObject(with: sample.rawJSON) as? [String: Any] else { throw Failure.invalidContract }
        if let punches = frame["punches"] as? [[String: Any]] {
            frame["punches"] = punches.filter { event in
                guard let candidate = event["candidate"] as? [String: Any],
                      let onset = candidate["tOnsetMs"] as? Double else { return false }
                return onset >= current.openedMs && (current.reliableOnsetAfterMs.map { onset > $0 } ?? true)
            }
        }
        if upperBodyObserved {
            // Explicit jab/cross policy, supplied ONLY for current, observed
            // shoulders/elbows/wrists. Recovered 'upper' presence requires hips;
            // do not fabricate hip landmarks or weaken classifier confidence.
            var presence = frame["presence"] as? [String: Any] ?? [:]
            presence["inFrame"] = true; presence["framing"] = "upper"; presence["tMs"] = captureMs
            frame["presence"] = presence
        }
        current.lastCaptureMs = captureMs; active = current
        let events: [Event] = try call("observe", [frame, deliveredMs])
        return .judged(events)
    }

    func tick(atMs: Double) throws -> [Event] {
        guard let active, active.readyMs != nil, atMs.isFinite, atMs >= active.openedMs else { return [] }
        return try call("tick", [atMs])
    }
    func suspend(atMs: Double) throws {
        guard atMs.isFinite else { throw Failure.invalidContract }
        _ = try raw("suspend", [atMs]); active = nil
    }
    func close(atMs: Double) throws -> [Event] {
        guard atMs.isFinite else { throw Failure.invalidContract }
        let events: [Event] = try call("close", [atMs]); active = nil
        return events
    }
    func reset() throws { _ = try raw("reset", []); active = nil }
    func summary() throws -> Summary { try call("summary", []) }

    private func raw(_ method: String, _ arguments: [Any]) throws -> Data {
        try kernel.responseReference(method, arguments: JSONSerialization.data(withJSONObject: arguments))
    }
    private func call<T: Decodable>(_ method: String, _ arguments: [Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: raw(method, arguments))
    }
}
