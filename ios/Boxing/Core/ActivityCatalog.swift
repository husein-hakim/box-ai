import Foundation

// Versioned, original development content. No media or recognition is implied.
enum ActivityKind: String, Codable, Sendable, CaseIterable { case warmup, boxing, strength, conditioning, core, mobility, cooldown }
enum TrainingMode: String, Codable, Sendable, CaseIterable { case shadowboxing, bag, pads, guided, camera
    var title: String { self == .camera ? "Camera · beta" : rawValue.capitalized }
}
enum ActivityDifficulty: Int, Codable, Sendable { case beginner = 1, intermediate = 2 }
enum PrescriptionKind: String, Codable, Sendable { case timed, repetitions }

struct PrescriptionSupport: Codable, Equatable, Sendable {
    let kind: PrescriptionKind
    let maxSets: Int
    let minWork: Int
    let maxWork: Int
    let maxReps: Int
    let maxRest: Int
    static let timed = Self(kind: .timed, maxSets: 6, minWork: 20, maxWork: 180, maxReps: 0, maxRest: 120)
    static let reps = Self(kind: .repetitions, maxSets: 4, minWork: 20, maxWork: 180, maxReps: 16, maxRest: 120)
}

struct CatalogActivity: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    let kind: ActivityKind
    let objective: String
    let difficulty: ActivityDifficulty
    let equipment: [String]
    let needsOpenSpace: Bool
    let setup: String
    let instructions: [String]
    let cues: [String]
    let mistakes: [String]
    let support: PrescriptionSupport
    let modes: [TrainingMode]
    var repsPerSide: Bool { ["ankle-rocks-v1", "trunk-turn-v1", "heel-slide-v1", "bird-dog-v1"].contains(id) }
    var coachReview: String { "Pending boxing-coach review" }
    // An absent original demonstration stays absent in both the catalog and UI.
    var demonstrationAvailable: Bool { false }
    func available(equipment: [String], openSpace: Bool, difficulty: ActivityDifficulty) -> Self? {
        guard self.difficulty.rawValue <= difficulty.rawValue, !needsOpenSpace || openSpace else { return nil }
        let allowed = modes.filter { mode in
            Set(requirements(for: mode)).isSubset(of: Set(equipment)) && (openSpace || (mode != .bag && mode != .pads))
        }
        guard !allowed.isEmpty else { return nil }
        return .init(id: id, title: title, kind: kind, objective: objective, difficulty: self.difficulty, equipment: self.equipment,
                     needsOpenSpace: needsOpenSpace, setup: setup, instructions: instructions, cues: cues, mistakes: mistakes, support: support, modes: allowed)
    }
    func setup(for mode: TrainingMode) -> String {
        switch mode {
        case .shadowboxing: return setup + " Shadowbox without contact. Keep every movement controlled."
        case .bag: return setup + " Check the bag is securely mounted. Use wraps and suitable gloves; start with light controlled contact and reset away from its swing."
        case .pads: return setup + " Work with a competent pad holder. Agree on the exact sequence and stop signal first. The holder presents stable targets; begin lightly and reset between repetitions."
        case .camera: return setup + " Noncontact camera practice: support the phone outside your reach. Keep your head, shoulders, elbows and hands visible. Jab/cross are cued one at a time with a reset; never strike the phone."
        case .guided: return setup
        }
    }
    func requirements(for mode: TrainingMode) -> [String] {
        equipment + (mode == .bag ? ["Punch bag", "Gloves", "Hand wraps"] : mode == .pads ? ["Focus pads", "Gloves", "Hand wraps", "Pad partner"] : [])
    }
}

struct CapabilityRegistry: Codable, Sendable {
    let catalogVersion = 2
    let guidedTraining = true
    let manualCompletion = true
    let livePadTraining = true
    let movementRecognition = true
    let cameraVerifiedPerformance = false
    let cameraActivities = CameraPlanningCapability.all
    let recognitionStatus = "Experimental on-device jab/cross recognition; accuracy varies by setup/device. No technique, power or contact grading."
    let animatedCoach = false
    let tacticalOpponent = false
    init() {}
    init(from decoder: Decoder) throws { self.init() } // Capabilities are app-owned, never enabled by decoded data.
    static let current = Self()
}

struct ActivityPrescription: Codable, Equatable, Sendable, Identifiable {
    var id: String
    var activityID: String
    var mode: TrainingMode
    var sets: Int
    var reps: Int // Per side where the catalog explicitly says “each side”. Zero for timed work.
    var workSeconds: Int // Timed interval, or a disclosed time allowance for a manually confirmed rep set.
    var restSeconds: Int
    var difficulty: ActivityDifficulty? = nil // Absent in older accepted prescriptions.
    var effectiveDifficulty: ActivityDifficulty { difficulty ?? ActivityCatalog.find(activityID)?.difficulty ?? .beginner }
    var supportsCameraChoice: Bool { CameraPlanningCapability.supports(activityID) && (mode == .camera || mode == .shadowboxing) }
    var estimatedSeconds: Int { sets * workSeconds + max(0, sets - 1) * restSeconds }
}

struct GuidedSession: Codable, Equatable, Sendable {
    var title: String
    var type: SessionType
    var activities: [ActivityPrescription]
    enum SessionType: String, Codable, Sendable { case technique, mixed, strength, conditioning, recovery, livePads }
    var estimatedSeconds: Int { activities.reduce(0) { $0 + $1.estimatedSeconds } }
    var equipment: [String] {
        Array(Set(activities.flatMap { ActivityCatalog.find($0.activityID)?.requirements(for: $0.mode) ?? [] })).sorted()
    }
    func validationErrors(equipment: [String], openSpace: Bool, difficulty: ActivityDifficulty, budget: Int) -> [String] {
        var errors: [String] = []
        if type == .livePads && !activities.contains(where: { $0.mode == .camera }) { errors.append("Live pad sessions need a supported camera block.") }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120 { errors.append("A short session title is required.") }
        if activities.isEmpty && type != .recovery { errors.append("Training sessions need at least one activity.") }
        if activities.count > 30 || Set(activities.map(\.id)).count != activities.count { errors.append("Use at most 30 uniquely identified activities.") }
        for item in activities {
            guard let activity = ActivityCatalog.find(item.activityID) else { errors.append("Unknown activity: \(item.activityID)"); continue }
            let support = activity.support
            if item.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || item.id.count > 120 { errors.append("Every block needs a stable, short ID.") }
            if item.effectiveDifficulty.rawValue < activity.difficulty.rawValue || item.effectiveDifficulty.rawValue > difficulty.rawValue { errors.append("Unsupported difficulty for \(activity.title).") }
            if item.mode == .camera && !CameraPlanningCapability.supports(item.activityID) { errors.append("Camera recognition is unavailable for \(activity.title).") }
            if !activity.modes.contains(item.mode) { errors.append("Unsupported mode for \(activity.title).") }
            if activity.difficulty.rawValue > difficulty.rawValue { errors.append("\(activity.title) exceeds your experience setting.") }
            if !Set(activity.requirements(for: item.mode)).isSubset(of: Set(equipment)) { errors.append("Missing equipment for \(activity.title).") }
            if (activity.needsOpenSpace || item.mode == .bag || item.mode == .pads) && !openSpace { errors.append("\(activity.title) needs more clear space.") }
            if !(1...support.maxSets).contains(item.sets) || !(support.minWork...support.maxWork).contains(item.workSeconds) || !(0...support.maxRest).contains(item.restSeconds) { errors.append("Unsupported timing for \(activity.title).") }
            if support.kind == .timed ? item.reps != 0 : !(1...support.maxReps).contains(item.reps) { errors.append("Unsupported repetitions for \(activity.title).") }
            if item.sets > 1 && item.restSeconds < 15 { errors.append("Allow at least 15 seconds between sets.") }
        }
        // Values are bounded before arithmetic to avoid overflowing on untrusted model output.
        if activities.allSatisfy({ (1...6).contains($0.sets) && (20...180).contains($0.workSeconds) && (0...120).contains($0.restSeconds) }) {
            if estimatedSeconds > budget { errors.append("The session exceeds your time budget, including rests.") }
        } else { errors.append("Invalid session duration.") }
        return errors
    }
}

enum ActivityCatalog {
    static func find(_ id: String) -> CatalogActivity? { all.first { $0.id == id } }
    static let all: [CatalogActivity] = [
        boxing("stance-guard-v1", "Stance & guard", objective: "Find a balanced stance you can return to.", setup: "Stand on a non-slip surface with room for one small step.", steps: ["Place your lead foot forward and rear foot slightly out to the side.", "Soften your knees, raise hands near your cheeks and keep your chin comfortably tucked.", "Shift your weight gently, then settle without narrowing your base."], cues: ["Hands home. Knees soft.", "Stay balanced."], mistakes: ["Standing on one line", "Locking the knees"], modes: [.shadowboxing]),
        boxing("jab-reset-v1", "Jab & reset", objective: "Extend the lead straight and return to guard.", setup: "Set your stance. Use light contact only with suitable equipment and supervision.", steps: ["Extend the lead hand on a straight path without locking the elbow.", "Keep the rear hand near your cheek.", "Bring the lead hand back along the same path and reset."], cues: ["Jab. Hand home.", "Stay relaxed."], mistakes: ["Reaching past your balance", "Dropping the rear hand"]),
        boxing("cross-reset-v1", "Cross & reset", objective: "Coordinate a controlled rear straight with your stance.", setup: "Set your guard and leave room to turn the rear foot.", steps: ["Turn the rear hip and foot gently as the rear hand travels straight.", "Keep the lead hand home and avoid locking the rear elbow.", "Return to guard and a stable stance."], cues: ["Turn. Cross. Reset.", "Keep your balance."], mistakes: ["Leaning beyond the front foot", "Over-rotating"]),
        boxing("lead-hook-v1", "Lead hook", objective: "Practise a compact lead hook with control.", setup: "Start in guard with clear space beside you. Begin slowly.", steps: ["Keep a comfortable bend in the lead elbow.", "Turn your lead side gently as the hand follows a short arc.", "Return the hand to guard without swinging past your balance."], cues: ["Small turn. Hand home."], mistakes: ["Wide swinging arm", "Twisting through a fixed knee"], level: .intermediate),
        boxing("rear-uppercut-v1", "Rear uppercut", objective: "Practise a compact upward punch.", setup: "Begin slowly in guard with space in front of you.", steps: ["Soften the knees slightly without a deep dip.", "Turn gently through your rear side as your rear hand takes a short upward path.", "Keep the lead hand home and return to guard."], cues: ["Compact movement. Reset."], mistakes: ["Dropping the hand first", "Throwing upward past your balance"], level: .intermediate),
        boxing("rear-hook-v1", "Rear hook", objective: "Practise a short rear-side hook with a balanced finish.", setup: "Start slowly in guard with clear space beside you.", steps: ["Keep a comfortable bend in the rear elbow and your lead hand home.", "Turn the rear hip and foot gently as the hand follows a short arc.", "Return to guard without swinging past your balance."], cues: ["Short arc. Hands home."], mistakes: ["Swinging the arm wide", "Over-rotating or forcing the knee"], level: .intermediate),
        boxing("lead-uppercut-v1", "Lead uppercut", objective: "Practise a compact upward lead-side punch.", setup: "Begin slowly from guard with space in front of you.", steps: ["Soften the knees slightly while keeping your rear hand home.", "Turn gently through the lead side as the lead hand follows a short upward path.", "Return to guard without leaning or lifting the chin."], cues: ["Compact lift. Reset."], mistakes: ["Dropping the hand before punching", "Leaning or dipping deeply"], level: .intermediate),
        boxing("jab-cross-reset-v1", "Jab–cross & reset", objective: "Link two controlled straight punches.", setup: "Set your stance and keep each punch light.", steps: ["Throw a relaxed lead straight.", "Return it as your rear straight travels out.", "Bring both hands home and reset before repeating."], cues: ["Jab. Cross. Reset."], mistakes: ["Rushing the return", "Feet becoming narrow"]),
        boxing("double-jab-v1", "Double jab", objective: "Repeat the jab while keeping your base.", setup: "Begin from guard at a controlled pace.", steps: ["Throw a light lead straight and bring it back.", "Repeat the jab without reaching.", "Reset your guard and stance."], cues: ["Jab. Jab. Reset."], mistakes: ["Pushing the second punch", "Leaning forward"]),
        boxing("one-two-hook-v1", "Jab–cross–hook", objective: "Connect straights with a compact lead hook.", setup: "Practise slowly with a stable stance.", steps: ["Throw a controlled jab and cross.", "Return the rear hand to guard as you turn into a short lead hook.", "Reset before starting again."], cues: ["Jab. Cross. Hook. Reset."], mistakes: ["Swinging the hook wide", "Rushing while off balance"], level: .intermediate),
        boxing("step-slide-v1", "Step & slide", objective: "Move without crossing or narrowing your feet.", setup: "Clear enough floor for two short steps in each direction.", steps: ["Step with the foot nearest the direction of travel.", "Slide the other foot to restore your usual stance width.", "Practise forward, backward and sideways at a walking pace."], cues: ["Small step. Restore your base."], mistakes: ["Crossing the feet", "Bouncing too far"], modes: [.shadowboxing], open: true),
        boxing("pivot-v1", "Small pivot", objective: "Change your angle while staying balanced.", setup: "Use a non-slip clear floor and begin with a small turn.", steps: ["Settle into a comfortable stance.", "Turn around the lead foot while the rear foot follows the arc.", "Reset your stance without forcing the knee."], cues: ["Small turn. Hands home."], mistakes: ["Twisting a fixed knee", "Overturning"], modes: [.shadowboxing], open: true),
        boxing("jab-step-v1", "Jab with a step", objective: "Coordinate a small step with a straight punch.", setup: "Leave space for one short step forward and back.", steps: ["Take a small lead-foot step as you jab.", "Bring the rear foot forward to restore your base.", "Return to guard and step back to reset."], cues: ["Small step. Jab. Reset."], mistakes: ["Lunging", "Dragging the rear foot"], modes: [.shadowboxing, .bag, .pads], open: true),
        boxing("slip-v1", "Small slip", objective: "Move the head a little while keeping your guard.", setup: "Practise without a partner throwing punches.", steps: ["Set a relaxed guard.", "Make a small torso turn to move the head just off the centre line.", "Return to centre and alternate sides without bending at the waist."], cues: ["Small slip. Eyes forward."], mistakes: ["Leaning too far", "Dropping the hands"], modes: [.shadowboxing]),
        boxing("high-cover-v1", "High cover & reset", objective: "Practise a compact defensive guard without impact.", setup: "Stand comfortably. No partner strikes are needed.", steps: ["Bring your gloves or hands close beside your forehead.", "Keep elbows near the body and eyes forward.", "Relax back into your normal guard."], cues: ["Cover. See. Reset."], mistakes: ["Closing the eyes", "Lifting elbows away"], modes: [.shadowboxing]),
        boxing("parry-v1", "Small lead-hand parry", objective: "Practise a small defensive hand movement.", setup: "Use noncontact shadowboxing with no incoming punches.", steps: ["Begin from guard.", "Move the lead hand a few centimetres across the centre line.", "Return it immediately to guard without reaching."], cues: ["Small movement. Hand home."], mistakes: ["Reaching to chase a punch", "Leaving the chin uncovered"], modes: [.shadowboxing]),
        boxing("slip-cross-v1", "Slip & cross", objective: "Return from a small slip with a controlled straight.", setup: "Practise slowly without an attacking partner.", steps: ["Make a small slip toward your rear side.", "Return toward centre as you extend the rear straight.", "Reset your guard and balance."], cues: ["Slip. Cross. Reset."], mistakes: ["Throwing while off balance", "Exaggerating the slip"], modes: [.shadowboxing], level: .intermediate),
        movement("warm-march-v1", "Easy march", .warmup, objective: "Ease into movement.", steps: ["Stand tall with space around you.", "March at a pace where you can talk comfortably.", "Let your arms move naturally."], cues: ["Easy pace."], mistakes: ["Starting too fast"]),
        movement("shoulder-circles-v1", "Shoulder circles", .mobility, objective: "Move the shoulders gently.", steps: ["Relax your arms beside you.", "Make slow comfortable shoulder circles.", "Change direction halfway through."], cues: ["Comfortable range."], mistakes: ["Forcing the range"]),
        movement("ankle-rocks-v1", "Ankle rocks", .mobility, objective: "Explore comfortable ankle movement.", steps: ["Stand near a stable wall for support.", "Keep one heel down and gently move that knee forward.", "Return and repeat on each side."], cues: ["Heel down. Move gently."], mistakes: ["Forcing through discomfort"], reps: true),
        movement("trunk-turn-v1", "Easy trunk turns", .mobility, objective: "Turn comfortably through the torso.", steps: ["Stand with knees soft.", "Turn gently left and return to centre.", "Turn right without forcing your range."], cues: ["Slow, comfortable turns."], mistakes: ["Forcing a fixed knee"], reps: true),
        movement("squat-v1", "Bodyweight squat", .strength, objective: "Practise controlled leg strength.", steps: ["Set feet at a comfortable width.", "Bend hips and knees to a comfortable depth with feet planted.", "Stand with control."], cues: ["Feet planted. Comfortable depth."], mistakes: ["Rushing the descent"], reps: true),
        movement("wall-push-v1", "Wall push-up", .strength, objective: "Build controlled pushing strength.", steps: ["Place hands on a stable wall at chest height.", "Keep your body aligned as you bend the elbows.", "Press away slowly."], cues: ["Body aligned."], mistakes: ["Dropping the hips"], reps: true, equipment: ["Stable wall"]),
        movement("bridge-v1", "Glute bridge", .strength, objective: "Practise controlled hip extension.", steps: ["Lie on your back with knees bent and feet planted.", "Lift hips only as far as is comfortable.", "Lower slowly."], cues: ["Lift gently. Lower slowly."], mistakes: ["Overarching the back"], reps: true),
        movement("heel-slide-v1", "Heel slide", .core, objective: "Move a leg while keeping the trunk steady.", steps: ["Lie on your back with knees bent.", "Slide one heel away without moving your trunk.", "Bring it back and alternate sides."], cues: ["Keep the trunk still."], mistakes: ["Reaching past control"], reps: true),
        movement("bird-dog-v1", "Bird dog", .core, objective: "Practise balance and trunk control.", steps: ["Begin on hands and knees.", "Extend opposite arm and leg only as far as you can stay balanced.", "Return slowly and alternate sides."], cues: ["Reach with control."], mistakes: ["Arching or twisting the back"], reps: true),
        movement("side-steps-v1", "Easy side steps", .conditioning, objective: "Build easy continuous movement.", steps: ["Clear a few steps of floor.", "Step side to side without crossing your feet.", "Keep the pace comfortable."], cues: ["Small steps. Easy breathing."], mistakes: ["Crossing feet"], open: true),
        movement("rope-v1", "Easy skipping", .conditioning, objective: "Practise relaxed rope intervals.", steps: ["Check the rope clears the floor and ceiling.", "Use low relaxed jumps on a suitable surface.", "Stop and reset whenever the rope catches."], cues: ["Low jumps. Relax."], mistakes: ["Jumping too high"], equipment: ["Skipping rope"], open: true),
        movement("easy-jog-v1", "Easy jog", .conditioning, objective: "Move at a conversational pace.", steps: ["Choose a clear safe outdoor route.", "Jog at a pace where you can talk.", "Walk whenever you need to."], cues: ["Keep it easy."], mistakes: ["Starting too fast"], equipment: ["Outdoor space"], open: true),
        movement("walk-reset-v1", "Easy walk & reset", .cooldown, objective: "Finish with easy movement.", steps: ["Walk slowly in a clear space.", "Let your shoulders relax and breathing settle.", "Finish when comfortable."], cues: ["Easy breathing. Relax."], mistakes: ["Stopping abruptly after hard work"])
    ]
    private static func boxing(_ id: String, _ title: String, objective: String, setup: String, steps: [String], cues: [String], mistakes: [String], modes: [TrainingMode] = [.shadowboxing, .bag, .pads], level: ActivityDifficulty = .beginner, open: Bool = false) -> CatalogActivity {
        .init(id: id, title: title, kind: .boxing, objective: objective, difficulty: level, equipment: [], needsOpenSpace: open, setup: setup, instructions: steps, cues: cues, mistakes: mistakes, support: .timed, modes: modes + (CameraPlanningCapability.supports(id) ? [.camera] : []))
    }
    private static func movement(_ id: String, _ title: String, _ kind: ActivityKind, objective: String, steps: [String], cues: [String], mistakes: [String], reps: Bool = false, equipment: [String] = [], open: Bool = false) -> CatalogActivity {
        .init(id: id, title: title, kind: kind, objective: objective, difficulty: .beginner, equipment: equipment, needsOpenSpace: open, setup: "Use a clear, comfortable surface. Stop if the movement is painful.", instructions: steps, cues: cues, mistakes: mistakes, support: reps ? .reps : .timed, modes: [.guided])
    }
}
