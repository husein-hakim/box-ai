import Foundation
import SwiftData

@Model final class AthleteProfile {
    var key: String = ""
    var name: String = ""
    var experience: String = ""
    var goal: String = ""
    var equipment: [String] = []
    var space: String = ""
    var nutritionInputData: Data?
    /// The fighter style the program should lean toward (encoded StyleFocus).
    var styleFocusData: Data? = nil
    var sessionMinutes: Int = 0
    init() { key = "primary"; name = ""; experience = "Beginner"; goal = "Build consistency"; equipment = []; space = "Small indoor space"; sessionMinutes = 10 }
}

@Model final class PlannedPractice {
    var id: UUID = UUID()
    var date: Date = Date.now
    var focusRaw: String = ""
    var rounds: Int = 0
    var workSeconds: Int = 0
    var restSeconds: Int = 0
    var source: String = ""
    var note: String = ""
    var sessionData: Data?
    var completionID: UUID?
    var planID: UUID?
    init(date: Date, focus: TrainingFocus, configuration: RoundConfiguration) {
        id = UUID(); self.date = date; focusRaw = focus.rawValue; rounds = configuration.rounds
        workSeconds = configuration.workSeconds; restSeconds = configuration.restSeconds
        source = "Local plan"; note = ""
    }
    var session: GuidedSession? {
        guard let sessionData, let session = try? JSONDecoder().decode(GuidedSession.self, from: sessionData),
              session.validationErrors(equipment: session.equipment, openSpace: true, difficulty: .intermediate, budget: 3600).isEmpty else { return nil }
        return session
    }
    var displayTitle: String { session?.title ?? (sessionData == nil ? String(localized: focus.title) : "Session unavailable") }
    var focus: TrainingFocus { TrainingFocus(rawValue: focusRaw) ?? .mixed }
    var configuration: RoundConfiguration { .init(rounds: rounds, workSeconds: workSeconds, restSeconds: restSeconds, cueInterval: 8) }
}

@Model final class WorkoutCompletion {
    var id: UUID = UUID()
    var date: Date = Date.now
    var routineID: String = ""
    var title: String = ""
    var exerciseIDs: [String] = []
    var notes: String = ""
    init(routineID: String, title: String, exerciseIDs: [String], notes: String = "") {
        id = UUID(); date = .now; self.routineID = routineID; self.title = title; self.exerciseIDs = exerciseIDs
        self.notes = notes
    }
}

@Model final class WorkoutDraft {
    var routineID: String = ""
    var exerciseIDs: [String] = []
    var notes: String = ""
    init(routineID: String, exerciseIDs: [String], notes: String) {
        self.routineID = routineID; self.exerciseIDs = exerciseIDs; self.notes = notes
    }
}

struct WorkoutRoutine: Identifiable {
    let id: String
    let title: LocalizedStringResource
    let category: LocalizedStringResource
    let equipment: String?
    let exercises: [Exercise]
    struct Exercise: Identifiable {
        let id: String
        let title: LocalizedStringResource
        let prescription: LocalizedStringResource
        let instruction: LocalizedStringResource
    }
    static let all: [WorkoutRoutine] = [
        .init(id: "strength-foundation", title: "Strength foundation", category: "Strength", equipment: nil, exercises: [
            .init(id: "squat", title: "Bodyweight squat", prescription: "2 sets of 8 · Rest 60 sec", instruction: "Use a comfortable depth, keep your feet planted and stand with control."),
            .init(id: "wall-push", title: "Wall push-up", prescription: "2 sets of 8 · Rest 60 sec", instruction: "Place hands on a stable wall. Keep your body aligned as you lower and press away."),
            .init(id: "bridge", title: "Glute bridge", prescription: "2 sets of 8 · Rest 60 sec", instruction: "Lie on your back with knees bent. Lift your hips comfortably, then lower slowly.")]),
        .init(id: "conditioning-easy", title: "Easy conditioning", category: "Conditioning", equipment: nil, exercises: [
            .init(id: "march", title: "March in place", prescription: "3 minutes at an easy pace", instruction: "Stay relaxed and choose a pace at which you can talk."),
            .init(id: "side-step", title: "Side steps", prescription: "3 × 30 sec · Rest 30 sec", instruction: "Step side to side without crossing your feet. Keep the steps small."),
            .init(id: "walk-reset", title: "Easy walk", prescription: "2 minutes", instruction: "Let your breathing settle at a comfortable walking pace.")]),
        .init(id: "core-control", title: "Core control", category: "Core", equipment: nil, exercises: [
            .init(id: "heel-slide", title: "Supine heel slide", prescription: "2 sets of 6 per side · Rest 45 sec", instruction: "Lie with knees bent. Slide one heel away and back while keeping your trunk still."),
            .init(id: "bird-dog", title: "Bird dog", prescription: "2 sets of 5 per side · Rest 45 sec", instruction: "From hands and knees, extend opposite arm and leg only as far as you can stay balanced.")]),
        .init(id: "mobility-reset", title: "Mobility reset", category: "Mobility", equipment: nil, exercises: [
            .init(id: "shoulder-roll", title: "Shoulder circles", prescription: "5 slow circles each direction", instruction: "Move gently through a comfortable range without forcing the stretch."),
            .init(id: "ankle-rock", title: "Ankle rocks", prescription: "8 per side", instruction: "With support nearby, bend one knee gently forward while keeping the heel down."),
            .init(id: "trunk-turn", title: "Easy trunk turns", prescription: "6 per side", instruction: "Turn gently through your torso while keeping your feet comfortably planted.")]),
        .init(id: "skipping-start", title: "Skipping starter", category: "Skipping", equipment: "Skipping rope", exercises: [
            .init(id: "rope-warmup", title: "Walk & ankle warm-up", prescription: "2 minutes", instruction: "Walk comfortably and make a few gentle ankle circles."),
            .init(id: "rope-rounds", title: "Easy rope intervals", prescription: "5 × 20 sec · Rest 40 sec", instruction: "Use low, relaxed jumps. Stop and reset if the rope catches; choose a clear, suitable surface.")]),
        .init(id: "run-walk", title: "Run–walk starter", category: "Running", equipment: "Outdoor space", exercises: [
            .init(id: "walk-in", title: "Walk to warm up", prescription: "3 minutes", instruction: "Choose a clear route and a comfortable walking pace."),
            .init(id: "run-walk-rounds", title: "Easy run–walk", prescription: "4 × (1 min jog + 1 min walk)", instruction: "Keep the jog conversational. Walk instead whenever you need to."),
            .init(id: "walk-out", title: "Walk to finish", prescription: "3 minutes", instruction: "Finish at a comfortable walking pace.")])
    ]
}

