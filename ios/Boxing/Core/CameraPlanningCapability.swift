import Foundation

/// Planning advertises implemented actions, not the classifier's entire label list.
struct CameraPlanningCapability: Codable, Sendable {
    let activityID: String
    var executionMode = "camera"
    var prescription = "timed rounds; sets=rounds; reps=0; workSeconds=20...180; restSeconds=15...120 between rounds"
    let behavior: String
    static let all: [Self] = [
        .init(activityID: "jab-reset-v1", behavior: "Lead straight with return to guard"),
        .init(activityID: "cross-reset-v1", behavior: "Rear straight with return to guard"),
        .init(activityID: "jab-cross-reset-v1", behavior: "Alternating jab and cross, cued ONE AT A TIME with resets; not continuous combination recognition")
    ]
    static func supports(_ activityID: String) -> Bool { all.contains { $0.activityID == activityID } }
}

extension ActivityPrescription {
    func cameraConfiguration(stance: BoxMaxxingJudge.Stance, suggestedLevel: PadLevel) -> PadConfiguration? {
        guard supportsCameraChoice else { return nil }
        var config = PadConfiguration()
        config.mode = .rounds; config.activityID = activityID; config.stance = stance
        config.level = difficulty.map { $0 == .beginner ? .beginner : .intermediate } ?? suggestedLevel
        // One set runs in the existing camera player; GuidedExecution owns
        // inter-set rest, block order and the complete assignment lifecycle.
        config.rounds = 1; config.workSeconds = workSeconds; config.restSeconds = 0
        return config.isValid ? config : nil
    }
}
