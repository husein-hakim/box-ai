import Foundation

/// Planning advertises implemented actions, not the classifier's entire label list.
struct CameraPlanningCapability: Codable, Sendable {
    /// Which camera player runs the block: one-at-a-time aimed pads, or the
    /// rhythm-based sparring engine (hooks, uppercuts, slips, ducks, combinations).
    enum Engine: String, Codable, Sendable { case pads, sparring }
    let activityID: String
    var executionMode = "camera"
    var prescription = "timed rounds; sets=rounds; reps=0; workSeconds=20...180; restSeconds=15...120 between rounds"
    let behavior: String
    var engine: Engine = .pads
    static let all: [Self] = [
        .init(activityID: "jab-reset-v1", behavior: "Lead straight with return to guard"),
        .init(activityID: "cross-reset-v1", behavior: "Rear straight with return to guard"),
        .init(activityID: "jab-cross-reset-v1", behavior: "Alternating jab and cross, cued ONE AT A TIME with resets; not continuous combination recognition")
    ] + SparringDrill.all.map {
        .init(activityID: $0.key, behavior: $0.value.isEmpty ? "Full sparring round: every punch, slip and duck in real combinations, on a rhythm, scored per move"
              : "Rhythm drill: the camera calls this drill's moves on the beat and scores each one", engine: .sparring)
    }.sorted { $0.activityID < $1.activityID }
    static func supports(_ activityID: String) -> Bool { all.contains { $0.activityID == activityID } }
    static func engine(for activityID: String) -> Engine? { all.first { $0.activityID == activityID }?.engine }
}

/// Camera drills run on the sparring engine: each drill repeats its moves on the
/// beat. Moves are stance-relative (lead/rear); an empty list is a full sparring round.
enum SparringDrill {
    enum Move: String, Codable, Sendable { case one, two, three, four, five, six, slipLead, slipRear, duck }
    static let all: [String: [Move]] = [
        "lead-hook-v1": [.three], "rear-hook-v1": [.four], "lead-uppercut-v1": [.five], "rear-uppercut-v1": [.six],
        "slip-v1": [.slipLead, .slipRear], "duck-v1": [.duck], "double-jab-v1": [.one, .one], "one-two-hook-v1": [.one, .two, .three],
        "slip-cross-v1": [.slipRear, .two], "one-two-upper-v1": [.one, .two, .five], "hook-cross-v1": [.three, .two],
        "upper-hook-v1": [.six, .three], "one-two-slip-v1": [.one, .two, .slipRear], "duck-hook-v1": [.duck, .three],
        "four-punch-v1": [.one, .two, .three, .two], "sparring-round-v1": []
    ]
    static func actions(for activityID: String, stance: BoxMaxxingJudge.Stance) -> [FightAction]? {
        guard let moves = all[activityID] else { return nil }
        let lead: FightAction.Side = stance == .orthodox ? .left : .right
        let rear: FightAction.Side = lead == .left ? .right : .left
        return moves.map { move in
            switch move {
            case .one: .straight(lead)
            case .two: .straight(rear)
            case .three: .hook(lead)
            case .four: .hook(rear)
            case .five: .uppercut(lead)
            case .six: .uppercut(rear)
            case .slipLead: .slip(lead)
            case .slipRear: .slip(rear)
            case .duck: .duck
            }
        }
    }
}

extension ActivityPrescription {
    func cameraConfiguration(stance: BoxMaxxingJudge.Stance, suggestedLevel: PadLevel) -> PadConfiguration? {
        guard supportsCameraChoice, CameraPlanningCapability.engine(for: activityID) == .pads else { return nil }
        var config = PadConfiguration()
        config.mode = .rounds; config.activityID = activityID; config.stance = stance
        config.level = difficulty.map { $0 == .beginner ? .beginner : .intermediate } ?? suggestedLevel
        // One set runs in the existing camera player; GuidedExecution owns
        // inter-set rest, block order and the complete assignment lifecycle.
        config.rounds = 1; config.workSeconds = workSeconds; config.restSeconds = 0
        return config.isValid ? config : nil
    }
}

extension ActivityPrescription {
    /// Sparring-engine configuration for one set of a camera drill.
    func sparringConfiguration(stance: BoxMaxxingJudge.Stance) -> SparringConfiguration? {
        guard mode == .camera, CameraPlanningCapability.engine(for: activityID) == .sparring,
              let actions = SparringDrill.actions(for: activityID, stance: stance) else { return nil }
        var config = SparringConfiguration()
        config.mode = actions.isEmpty ? .arcade : .drill
        config.sequence = actions.isEmpty ? nil : actions
        config.drillTitle = ActivityCatalog.find(activityID)?.title
        config.difficulty = effectiveDifficulty == .beginner ? .rookie : .contender
        config.stance = stance
        config.rounds = 1
        config.roundSeconds = max(20, workSeconds)
        return config
    }
}
