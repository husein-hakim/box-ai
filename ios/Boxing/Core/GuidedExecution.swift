import Foundation

/// A single assignment executor. Guided sets require a check-in; camera sets
/// retain measured observations separately from completion of their timed work.
struct GuidedExecution: Codable, Sendable {
    enum Phase: String, Codable, Sendable { case briefing, instruction, work, confirmation, rest, recap }
    enum Outcome: String, Codable, Sendable { case completed, partial, skipped, notStarted }
    struct CameraSet: Codable, Sendable, Identifiable, Equatable {
        var id: String { "\(blockID):\(set):\(continuedGuided)" }
        let blockID: String
        let set: Int
        let state: PadTrainingState
        let continuedGuided: Bool
        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.id == rhs.id && lhs.state.configuration == rhs.state.configuration &&
            lhs.state.phase == rhs.state.phase && lhs.state.attempts == rhs.state.attempts &&
            lhs.state.activeSeconds == rhs.state.activeSeconds && lhs.state.workSeconds == rhs.state.workSeconds &&
            lhs.state.completedRounds == rhs.state.completedRounds && lhs.state.endedEarly == rhs.state.endedEarly &&
            lhs.state.retries == rhs.state.retries && lhs.state.uncertainAttempts == rhs.state.uncertainAttempts
        }
    }
    struct ActivityResult: Codable, Equatable, Sendable {
        var confirmedSets = 0
        var attemptedSets = 0
        var confirmedReps = 0
        var timedSeconds: Double = 0
        var skipped = false
        var cameraSets: [CameraSet]? = nil
        var guidedCheckIns: Int? = nil
    }
    let session: GuidedSession
    let assignmentID: UUID?
    private(set) var phase: Phase = .briefing
    private(set) var index = 0
    private(set) var set = 1
    private(set) var elapsed = 0.0
    private(set) var activeSeconds = 0.0
    private(set) var paused = false
    private(set) var endedEarly = false
    private(set) var results: [ActivityResult]
    var camera: PadTrainingState? = nil
    private(set) var modeOverrides: [String: TrainingMode]? = nil
    private(set) var preferredCameraStance: BoxMaxxingJudge.Stance? = nil
    private var lastTick: Double?
    enum CodingKeys: String, CodingKey { case session, assignmentID, phase, index, set, elapsed, activeSeconds, paused, endedEarly, results, camera, modeOverrides, preferredCameraStance }
    init(session: GuidedSession, assignmentID: UUID? = nil) {
        self.session = session; self.assignmentID = assignmentID
        results = session.activities.map { _ in ActivityResult() }
    }
    var current: ActivityPrescription? { session.activities.indices.contains(index) ? session.activities[index] : nil }
    var currentMode: TrainingMode { current.map { modeOverrides?[$0.id] ?? $0.mode } ?? .guided }
    var totalActiveSeconds: Double { activeSeconds + (camera?.activeSeconds ?? 0) }
    mutating func chooseMode(_ mode: TrainingMode) {
        guard phase == .instruction, elapsed == 0, let current, current.supportsCameraChoice,
              mode == .camera || mode == .shadowboxing else { return }
        if modeOverrides == nil { modeOverrides = [:] }
        modeOverrides?[current.id] = mode
    }
    mutating func startCamera(_ configuration: PadConfiguration) {
        guard phase == .instruction, !paused, currentMode == .camera, let current,
              configuration.activityID == current.activityID, configuration.mode == .rounds,
              configuration.rounds == 1, configuration.workSeconds == current.workSeconds, configuration.isValid else { return }
        preferredCameraStance = configuration.stance
        camera = PadTrainingState(configuration: configuration); phase = .work; lastTick = nil
    }
    var duration: Double { Double(phase == .rest ? current?.restSeconds ?? 0 : current?.workSeconds ?? 0) }
    var remaining: Double { max(0, duration - elapsed) }
    var isTiming: Bool { (phase == .work || phase == .rest) && !paused }
    mutating func begin() { guard phase == .briefing else { return }; phase = .instruction }
    mutating func startSet(at now: Double) {
        guard phase == .instruction, current != nil else { return }
        phase = .work; elapsed = 0; paused = false; lastTick = now
    }
    mutating func tick(at now: Double) {
        guard camera == nil, isTiming, let previous = lastTick, now >= previous else { return }
        let used = min(now - previous, remaining)
        lastTick = now; elapsed += used; activeSeconds += used
        if phase == .work { results[index].timedSeconds += used }
        if elapsed >= duration {
            lastTick = nil
            if phase == .work { phase = .confirmation }
            else { phase = .instruction; elapsed = 0 }
        }
    }
    mutating func pause(at now: Double) { tick(at: now); paused = true; lastTick = nil }
    mutating func resume(at now: Double) { paused = false; lastTick = isTiming ? now : nil }
    mutating func finishSet(at now: Double) {
        guard phase == .work else { return }; tick(at: now); phase = .confirmation; paused = false; lastTick = nil
    }
    mutating func confirm(reps: Int? = nil, at now: Double) {
        guard phase == .confirmation, let item = current else { return }
        let kind = ActivityCatalog.find(item.activityID)?.support.kind
        let actual = min(item.reps, max(0, reps ?? item.reps))
        results[index].attemptedSets += 1
        results[index].guidedCheckIns = (results[index].guidedCheckIns ?? (results[index].attemptedSets - 1)) + 1
        results[index].confirmedReps += actual
        if kind == .repetitions ? actual >= item.reps : elapsed >= Double(item.workSeconds) - 0.001 { results[index].confirmedSets += 1 }
        advanceAfterSet(at: now, item: item)
    }
    private mutating func advanceAfterSet(at now: Double, item: ActivityPrescription) {
        paused = false
        if set < item.sets {
            set += 1; elapsed = 0
            if item.restSeconds > 0 { phase = .rest; lastTick = paused ? nil : now }
            else { phase = .instruction; lastTick = nil }
        } else { nextActivity() }
    }
    /// The camera player finishes one prescribed set, never the whole assignment.
    mutating func finishCameraSet(at now: Double) {
        guard let state = camera, state.phase == .recap, let item = current else { return }
        retainCamera(state, continuedGuided: false)
        results[index].attemptedSets += 1
        if !state.endedEarly && state.completedRounds == 1 && state.workSeconds >= Double(item.workSeconds) - 0.01 {
            results[index].confirmedSets += 1 // Timed work completed, not successful punch count.
        }
        camera = nil; elapsed = 0
        advanceAfterSet(at: now, item: item)
    }
    /// Explicit fallback keeps elapsed work and observations. The remaining time
    /// uses the ordinary guided timer and requires the user's own check-in.
    mutating func continueGuided(at now: Double) {
        guard let item = current, item.supportsCameraChoice else { return }
        if let state = camera {
            retainCamera(state, continuedGuided: true)
            elapsed = min(Double(item.workSeconds), state.workSeconds)
            camera = nil; phase = .work; paused = true; lastTick = nil
        }
        if modeOverrides == nil { modeOverrides = [:] }
        modeOverrides?[item.id] = .shadowboxing
    }
    private mutating func retainCamera(_ state: PadTrainingState, continuedGuided: Bool) {
        guard let item = current else { return }
        if results[index].cameraSets == nil { results[index].cameraSets = [] }
        var snapshot = state
        if snapshot.phase != .recap { snapshot.stop() }
        results[index].cameraSets?.append(.init(blockID: item.id, set: set, state: snapshot, continuedGuided: continuedGuided))
        results[index].timedSeconds += state.workSeconds
        activeSeconds += state.activeSeconds
    }
    mutating func skip(at now: Double) {
        guard phase != .briefing && phase != .recap else { return }
        if let state = camera { retainCamera(state, continuedGuided: false); camera = nil }
        tick(at: now); results[index].skipped = true; nextActivity()
    }
    mutating func end(at now: Double) {
        if var state = camera { state.stop(); retainCamera(state, continuedGuided: false); camera = nil }
        tick(at: now); endedEarly = true; phase = .recap; paused = false; lastTick = nil
    }
    private mutating func nextActivity() {
        index += 1; set = 1; elapsed = 0; paused = false; lastTick = nil
        phase = index == session.activities.count ? .recap : .instruction
    }
    func outcome(at index: Int) -> Outcome {
        let result = results[index]
        if result.confirmedSets == session.activities[index].sets { return .completed }
        if result.timedSeconds > 0 || result.attemptedSets > 0 { return .partial }
        return result.skipped ? .skipped : .notStarted
    }
    func restored() -> Self {
        var copy = self; copy.lastTick = nil; copy.camera = camera?.restored()
        if phase != .briefing && phase != .recap { copy.paused = true }
        return copy
    }
    var isValidCheckpoint: Bool {
        guard !session.activities.isEmpty, session.validationErrors(equipment: session.equipment, openSpace: true, difficulty: .intermediate, budget: 3600).isEmpty,
              results.count == session.activities.count, (0...session.activities.count).contains(index),
              (index < session.activities.count || phase == .recap), (1...6).contains(set),
              elapsed.isFinite, elapsed >= 0, activeSeconds.isFinite, activeSeconds >= 0,
              activeSeconds <= Double(session.estimatedSeconds) + 0.01 else { return false }
        if let current, (set > current.sets || elapsed > Double(max(current.workSeconds, current.restSeconds)) + 0.01) { return false }
        if let camera {
            guard phase == .work, let current, currentMode == .camera, current.supportsCameraChoice,
                  camera.isValidCheckpoint, camera.configuration.activityID == current.activityID,
                  camera.configuration.rounds == 1, camera.configuration.workSeconds == current.workSeconds else { return false }
        }
        if let modeOverrides, !modeOverrides.allSatisfy({ id, mode in
            session.activities.contains { $0.id == id && $0.supportsCameraChoice } && (mode == .camera || mode == .shadowboxing)
        }) { return false }
        return results.enumerated().allSatisfy { i, result in
            let item = session.activities[i]
            return (0...item.sets).contains(result.confirmedSets) && (result.confirmedSets...item.sets).contains(result.attemptedSets) &&
                (0...(item.reps * item.sets)).contains(result.confirmedReps) && result.timedSeconds.isFinite && result.timedSeconds >= 0 && result.timedSeconds <= Double(item.workSeconds * item.sets) + 0.01 &&
                (result.cameraSets ?? []).allSatisfy { $0.blockID == item.id && (1...item.sets).contains($0.set) && $0.state.isValidCheckpoint }
        }
    }
}

struct GuidedSummary: Codable, Sendable {
    let execution: GuidedExecution
    var feedback: String?
    var title: String { execution.session.title }
    var completed: Int { execution.results.indices.filter { execution.outcome(at: $0) == .completed }.count }
    var partial: Int { execution.results.indices.filter { execution.outcome(at: $0) == .partial }.count }
    var skipped: Int { execution.results.indices.filter { execution.outcome(at: $0) == .skipped }.count }
}
