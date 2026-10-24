import Foundation
import SwiftData

struct WorkoutProposal: Codable, Sendable {
    let title: String
    let routineIDs: [String]
    let reason: String
    func isValid(allowedSeconds: [String: Int], budgetSeconds: Int) -> Bool {
        !title.isEmpty && title.count <= 200 && !reason.isEmpty && reason.count <= 2000 &&
        (1...3).contains(routineIDs.count) && Set(routineIDs).count == routineIDs.count &&
        routineIDs.allSatisfy { allowedSeconds[$0] != nil } && routineIDs.reduce(0) { $0 + (allowedSeconds[$1] ?? budgetSeconds + 1) } <= budgetSeconds
    }
}

@Model final class SavedWorkoutPlan {
    @Attribute(.unique) var id: UUID
    var date: Date
    var title: String
    var routineIDs: [String]
    var reason: String
    init(_ proposal: WorkoutProposal) { id = UUID(); date = .now; title = proposal.title; routineIDs = proposal.routineIDs; reason = proposal.reason }
}

extension WorkoutRoutine {
    var estimatedMinutes: Int { Int(ceil(Double(guidedSession.estimatedSeconds) / 60)) }
    var equipmentDescription: String { guidedSession.equipment.isEmpty ? "No equipment" : guidedSession.equipment.joined(separator: " · ") }
    func isEligible(equipment: [String], space: String) -> Bool {
        guidedSession.validationErrors(equipment: equipment.map { $0 == "Heavy bag" ? "Punch bag" : $0 }, openSpace: space != "Small indoor space", difficulty: .intermediate, budget: 3600).isEmpty
    }
}

extension WorkoutRoutine {
    /// Explicit catalog adapter; these are practice presets, never generated personalized plans.
    var guidedSession: GuidedSession {
        typealias Item = ActivityPrescription
        func timed(_ id: String, _ activity: String, _ seconds: Int, sets: Int = 1, rest: Int = 0) -> Item {
            .init(id: id, activityID: activity, mode: .guided, sets: sets, reps: 0, workSeconds: seconds, restSeconds: rest)
        }
        func reps(_ id: String, _ activity: String, _ count: Int, sets: Int = 2, rest: Int = 45) -> Item {
            .init(id: id, activityID: activity, mode: .guided, sets: sets, reps: count, workSeconds: 40, restSeconds: rest)
        }
        let work: [Item]
        switch id {
        case "strength-foundation": work = [reps("squat", "squat-v1", 8, rest: 60), reps("wall", "wall-push-v1", 8, rest: 60), reps("bridge", "bridge-v1", 8, rest: 60)]
        case "conditioning-easy": work = [timed("march", "warm-march-v1", 180), timed("steps", "side-steps-v1", 30, sets: 3, rest: 30)]
        case "core-control": work = [reps("heel", "heel-slide-v1", 6), reps("bird", "bird-dog-v1", 5)]
        case "mobility-reset": work = [timed("shoulders", "shoulder-circles-v1", 20), reps("ankles", "ankle-rocks-v1", 8, sets: 1), reps("turn", "trunk-turn-v1", 6, sets: 1)]
        case "skipping-start": work = [timed("rope", "rope-v1", 20, sets: 5, rest: 40)]
        default: work = [timed("jog", "easy-jog-v1", 60, sets: 4, rest: 60), timed("last-walk", "walk-reset-v1", 60)]
        }
        return .init(title: String(localized: title), type: id == "strength-foundation" ? .strength : .mixed,
                     activities: [timed("warmup", "warm-march-v1", id == "run-walk" ? 180 : 60)] + work + [timed("cooldown", "walk-reset-v1", id == "run-walk" ? 180 : 60)])
    }
}


extension WorkoutProposal {
    var guidedSession: GuidedSession? { WorkoutRoutine.combined(ids: routineIDs, title: title) }
}
extension SavedWorkoutPlan {
    var guidedSession: GuidedSession? { WorkoutRoutine.combined(ids: routineIDs, title: title) }
}
extension WorkoutRoutine {
    static func combined(ids: [String], title: String) -> GuidedSession? {
        guard !ids.isEmpty, ids.allSatisfy({ id in all.contains { $0.id == id } }) else { return nil }
        let activities = ids.enumerated().flatMap { index, id -> [ActivityPrescription] in
            guard let routine = all.first(where: { $0.id == id }) else { return [] }
            return routine.guidedSession.activities.map { item in
                var copy = item; copy.id = "routine-\(index)-" + item.id; return copy
            }
        }
        return .init(title: title, type: .mixed, activities: activities)
    }
}
