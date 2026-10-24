import Foundation
import SwiftData

struct PlanningConstraints: Codable, Equatable, Sendable {
    let experience: String
    let goal: String
    let stance: String
    let equipment: [String]
    let openSpace: Bool
    let space: String
    let selectedDays: [Int]
    let minutes: Int
    var difficulty: ActivityDifficulty { experience == "Beginner" ? .beginner : .intermediate }
}
struct PlanningAvailabilityDay: Codable, Sendable {
    let offset: Int
    let localDate: String
    let weekdayName: String
    let weekday: Int
    let trainingAllowed: Bool
}
struct PlanningContext: Codable, Sendable {
    let startDate: Date
    let requestedAt: Date
    let timeZoneID: String
    let localSchedule: [PlanningAvailabilityDay]
    let constraints: PlanningConstraints
    let history: [String]
    let feedback: String
    let catalog: [CatalogActivity]
    let capabilities: CapabilityRegistry
    var trainingOffsets: Set<Int> { Set(localSchedule.filter(\.trainingAllowed).map(\.offset)) }

}
struct TrainingPlanProposal: Codable, Sendable {
    struct Day: Codable, Sendable, Identifiable {
        var offset: Int
        var session: GuidedSession
        var rationale: String
        var id: Int { offset }
    }
    var title: String
    var progression: String
    var days: [Day]
    func errors(context: PlanningContext) -> [String] {
        var errors: [String] = []
        if title.isEmpty || title.count > 120 || progression.isEmpty || progression.count > 1500 { errors.append("The plan needs a concise title and progression explanation.") }
        guard days.count == 7, Set(days.map(\.offset)) == Set(0..<7) else { return errors + ["The plan must cover all seven days exactly once."] }
        var consecutiveTraining = 0
        var previousStrength = false
        for day in days.sorted(by: { $0.offset < $1.offset }) {
            errors += day.session.validationErrors(equipment: context.constraints.equipment, openSpace: context.constraints.openSpace, difficulty: context.constraints.difficulty, budget: context.constraints.minutes * 60).map { "Day \(day.offset): " + $0 }
            if day.rationale.isEmpty || day.rationale.count > 1000 { errors.append("Each day needs a short rationale.") }
            let actualWeekday = context.localSchedule.first { $0.offset == day.offset }?.weekdayName.lowercased()
            let words = Set(day.rationale.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            let weekdayWords = Set(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"])
            if words.intersection(weekdayWords).contains(where: { $0 != actualWeekday }) {
                errors.append("Day \(day.offset): the rationale contains an incorrect weekday. Omit weekday names; the app renders the local date.")
            }
            for block in day.session.activities {
                if !context.catalog.contains(where: { $0.id == block.activityID && $0.modes.contains(block.mode) }) {
                    errors.append("Day \(day.offset): block \(block.id) is outside the supplied activity/mode catalog.")
                }
            }
            let kinds = day.session.activities.compactMap { ActivityCatalog.find($0.activityID)?.kind }
            if !day.session.activities.isEmpty && (kinds.first != .warmup || kinds.last != .cooldown) { errors.append("Day \(day.offset) needs a warm-up first and cooldown last.") }
            let recovery = day.session.type == .recovery
            if !context.trainingOffsets.contains(day.offset) && !recovery { errors.append("Training must fit your chosen days.") }
            if recovery && kinds.contains(where: { ![ActivityKind.warmup, .mobility, .cooldown].contains($0) }) { errors.append("Recovery sessions may only use easy warm-up, mobility and cooldown activities.") }
            consecutiveTraining = recovery ? 0 : consecutiveTraining + 1
            if consecutiveTraining > 2 { errors.append("Include a recovery day after two training days.") }
            let strength = kinds.contains(.strength)
            if strength && previousStrength { errors.append("Separate strength sessions with a recovery or different training day.") }
            previousStrength = strength
        }
        if !days.contains(where: { $0.session.type != .recovery }) { errors.append("Include training on at least one chosen day.") }
        return Array(Set(errors)).sorted()
    }
}

@Model final class AcceptedTrainingPlan {
    @Attribute(.unique) var id: UUID
    var acceptedAt: Date
    var payload: Data
    var contextPayload: Data
    init(proposal: TrainingPlanProposal, context: PlanningContext) throws {
        id = UUID(); acceptedAt = .now
        payload = try JSONEncoder().encode(proposal); contextPayload = try JSONEncoder().encode(context)
    }
}

extension AppStore {
    var planningConstraints: PlanningConstraints {
        .init(experience: profile.experience, goal: profile.goal, stance: stance, equipment: activityEquipment.sorted(), openSpace: hasOpenSpace,
              space: profile.space, selectedDays: selectedDays.sorted(), minutes: profile.sessionMinutes)
    }
    func planningContext(feedback: String = "", from date: Date = .now, calendar: Calendar = .current) -> PlanningContext {
        let recent = history.prefix(10).map { record in
            let summary = record.guided
            let cameraSets = summary?.execution.results.flatMap { $0.cameraSets ?? [] } ?? []
            let source = cameraSets.isEmpty && record.pad == nil ? "Guided/self-reported, no recognition." : "Camera beta: \(cameraSets.reduce(0) { $0 + $1.state.attempts.filter(\.isHit).count } + (record.pad?.attempts.filter(\.isHit).count ?? 0)) recognised responses; observations are experimental, not technique grades. Tracking/aim uncertainty is separate from misses."
            return "\(record.date.ISO8601Format()): \(summary?.title ?? String(localized: record.focus.title)); \(Int(record.workSeconds)) sec timed; \(summary?.completed ?? record.completedRounds) completed; \(summary?.partial ?? 0) partial; \(summary?.skipped ?? record.skippedBlocks) skipped. Feedback: \(summary?.feedback?.prefix(500) ?? ""). \(source)"
        } + workouts.prefix(5).map { "\($0.date.ISO8601Format()): \($0.title); \($0.exerciseIDs.count) manually confirmed exercises. Feedback: \($0.notes.prefix(500))" }
        let start = calendar.startOfDay(for: date)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let schedule = (0..<7).compactMap { offset -> PlanningAvailabilityDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let weekday = calendar.component(.weekday, from: day)
            return .init(offset: offset, localDate: formatter.string(from: day), weekdayName: weekdays[weekday - 1], weekday: weekday, trainingAllowed: selectedDays.contains(weekday))
        }
        return .init(startDate: start, requestedAt: .now, timeZoneID: calendar.timeZone.identifier, localSchedule: schedule,
                     constraints: planningConstraints, history: recent, feedback: String(feedback.prefix(1000)),
                     catalog: ActivityCatalog.all.compactMap { $0.available(equipment: activityEquipment, openSpace: hasOpenSpace, difficulty: activityDifficulty) }, capabilities: .current)
    }
    @discardableResult func acceptTrainingPlan(_ proposal: TrainingPlanProposal, context requestContext: PlanningContext) -> Bool {
        guard requestContext.constraints == planningConstraints, requestContext.timeZoneID == TimeZone.current.identifier,
              requestContext.startDate >= Calendar.current.startOfDay(for: .now),
              (0...86_400).contains(Date.now.timeIntervalSince(requestContext.requestedAt)),
              proposal.errors(context: requestContext).isEmpty else {
            storageNotice = "Your profile, schedule or draft changed. Generate a fresh plan before accepting."; return false
        }
        let dates = proposal.days.compactMap { Calendar.current.date(byAdding: .day, value: $0.offset, to: requestContext.startDate) }
        guard dates.count == 7, !plan.contains(where: { existing in dates.contains { Calendar.current.isDate($0, inSameDayAs: existing.date) } }) else {
            storageNotice = "These dates already have accepted assignments. Keep them, or explicitly remove the unwanted upcoming assignments before accepting a new plan."; return false
        }
        do {
            let accepted = try AcceptedTrainingPlan(proposal: proposal, context: requestContext)
            context.insert(accepted)
            for day in proposal.days {
                guard let date = Calendar.current.date(byAdding: .day, value: day.offset, to: requestContext.startDate) else { throw CocoaError(.coderInvalidValue) }
                let item = PlannedPractice(date: date, focus: .mixed, configuration: .init())
                item.source = "Personalized plan"; item.note = day.rationale; item.planID = accepted.id
                item.sessionData = try JSONEncoder().encode(day.session); context.insert(item)
            }
            return persist()
        } catch { failedSave(); return false }
    }
}
