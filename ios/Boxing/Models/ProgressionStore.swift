import Foundation
import SwiftData

extension AppStore {
    /// Plain values for the progression engine, read from saved records only.
    var progressionSnapshot: ProgressionSnapshot {
        var snapshot = ProgressionSnapshot()
        snapshot.sessions = history.map { .init(id: $0.id, date: $0.date, workSeconds: $0.workSeconds, finished: $0.finished, assignmentID: $0.assignmentID, sparring: $0.sparring) }
        snapshot.assignments = plan.map { .init(id: $0.id, date: $0.date, planID: $0.planID, isTraining: $0.session?.activities.isEmpty == false, isComplete: assignmentIsComplete($0)) }
        snapshot.meals = meals.map { .init(id: $0.id, date: $0.date, protein: $0.protein) }
        snapshot.water = waterEntries.map { .init(date: $0.date, millilitres: $0.millilitres) }
        snapshot.workouts = workouts.map { .init(id: $0.id, date: $0.date) }
        snapshot.proteinTarget = targets.protein
        snapshot.waterTarget = targets.water
        return snapshot
    }
    var progression: ProgressionState { Progression.compute(progressionSnapshot) }
    /// Sparring options opened by rank or by beating a score challenge.
    var unlocks: UnlockState { RankUnlocks.state(level: progression.level, sparring: history.compactMap(\.sparring)) }
}

/// Remembers what the user has already been shown, so level-ups, new ranks and
/// badges are celebrated exactly once. Existing history is never celebrated.
struct ProgressionSeen {
    private static let levelKey = "progression.seenLevel"
    private static let badgesKey = "progression.seenBadges"
    struct Celebration: Identifiable, Equatable {
        enum Kind: Equatable { case level(Int), rank(BoxRank), badge(BadgeState) }
        let kind: Kind
        var id: String {
            switch kind {
            case .level(let n): "level-\(n)"
            case .rank(let r): "rank-\(r.index)"
            case .badge(let b): "badge-\(b.id)-\(b.count)"
            }
        }
    }
    /// New celebrations since last time; records the current state as seen.
    static func update(with state: ProgressionState, defaults: UserDefaults = .standard) -> [Celebration] {
        let counts = Dictionary(uniqueKeysWithValues: state.badges.map { ($0.id, $0.count) })
        guard defaults.object(forKey: levelKey) != nil else {
            defaults.set(state.level, forKey: levelKey); defaults.set(counts, forKey: badgesKey)
            return []
        }
        let seenLevel = defaults.integer(forKey: levelKey)
        let seenBadges = defaults.dictionary(forKey: badgesKey) as? [String: Int] ?? [:]
        var out: [Celebration] = []
        if state.level > seenLevel {
            if Progression.rank(forLevel: seenLevel).index < state.rank.index { out.append(.init(kind: .rank(state.rank))) }
            else { out.append(.init(kind: .level(state.level))) }
        }
        for badge in state.badges where badge.count > (seenBadges[badge.id] ?? 0) { out.append(.init(kind: .badge(badge))) }
        defaults.set(state.level, forKey: levelKey); defaults.set(counts, forKey: badgesKey)
        return out
    }
}

extension AppStore {
    /// The most recently accepted program week.
    var latestAcceptedPlan: TrainingPlanProposal? {
        let latest = (try? context.fetch(FetchDescriptor<AcceptedTrainingPlan>()))?.max { $0.acceptedAt < $1.acceptedAt }
        return latest.flatMap { try? JSONDecoder().decode(TrainingPlanProposal.self, from: $0.payload) }
    }

    /// Four weeks of real training, digested for the next program.
    var adaptiveSummary: AdaptiveSummary {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = plan.filter { $0.date < today }.map { item in
            AdaptiveSummary.PlanDay(date: item.date, isTraining: item.session?.activities.isEmpty == false || (item.sessionData == nil && item.planID == nil),
                                    completion: assignmentIsComplete(item), partial: assignmentRecord(item) != nil)
        }
        let byDay = Dictionary(grouping: meals, by: { calendar.startOfDay(for: $0.date) })
        let fortnight = calendar.date(byAdding: .day, value: -14, to: today) ?? today
        let proteinHits = targets.protein > 0 ? byDay.filter { $0.key >= fortnight && $0.key < today && $0.value.reduce(0) { $0 + $1.protein } >= targets.protein }.count : 0
        let last = latestAcceptedPlan
        return AdaptiveSummary.build(.init(now: .now, calendar: calendar, history: history, plan: days, mealDays: Set(byDay.keys), proteinHitDays: proteinHits,
                                           progression: progression, unlocks: unlocks, stance: stance == "Southpaw" ? .southpaw : .orthodox,
                                           lastPlan: last.map { ($0.title, $0.progression) }))
    }

    /// True when the accepted program has no training left from today on.
    var nextWeekDue: Bool {
        let today = Calendar.current.startOfDay(for: .now)
        let programmed = plan.filter { $0.planID != nil }
        guard !programmed.isEmpty else { return false }
        return !programmed.contains { $0.date >= today && !assignmentIsComplete($0) && $0.session?.activities.isEmpty == false }
    }

    /// First free day for a new week: today, or the day after the last planned assignment.
    var nextPlanStart: Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        guard let last = plan.map(\.date).max(), last >= today, let after = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: last)) else { return today }
        return after
    }
}
