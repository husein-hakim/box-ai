import Foundation

/// XP, levels, ranks and badges, derived entirely from saved records.
///
/// Nothing here is stored as a running total: the ledger is recomputed from the
/// user's real history every time, so XP cannot drift, double-count or be
/// invented. Every award has a stable ID tied to the record or day it came from.
/// XP rewards consistency and real work; it is not a measure of boxing ability.
struct ProgressionSnapshot: Sendable {
    struct Session: Sendable {
        var id: UUID
        var date: Date
        var workSeconds: Double
        var finished: Bool
        var assignmentID: UUID?
        var sparring: SparringSummary?
    }
    struct Assignment: Sendable {
        var id: UUID
        var date: Date
        var planID: UUID?
        var isTraining: Bool
        var isComplete: Bool
    }
    struct Meal: Sendable { var id: UUID; var date: Date; var protein: Double }
    struct Water: Sendable { var date: Date; var millilitres: Int }
    struct Workout: Sendable { var id: UUID; var date: Date }

    var sessions: [Session] = []
    var assignments: [Assignment] = []
    var meals: [Meal] = []
    var water: [Water] = []
    var workouts: [Workout] = []
    var proteinTarget: Double = 0
    var waterTarget: Int = 0
    var calendar: Calendar = .current
}

struct XPEvent: Identifiable, Equatable, Sendable {
    enum Category: String, Sendable { case training, plan, sparring, fuel, streak, badge }
    let id: String
    let date: Date
    let amount: Int
    let title: String
    let category: Category
    /// The saved session this XP came from, if any.
    var sessionID: UUID? = nil
}

struct BoxRank: Equatable, Sendable, Identifiable {
    let index: Int
    let title: String
    let minimumLevel: Int
    let symbol: String
    var id: Int { index }
}

struct BadgeDefinition: Identifiable, Equatable, Sendable {
    enum Group: String, Sendable, CaseIterable { case training, sparring, fuel }
    let id: String
    let title: String
    let detail: String
    let symbol: String
    let group: Group
    let repeatable: Bool
}

struct BadgeState: Identifiable, Equatable, Sendable {
    let definition: BadgeDefinition
    /// Times earned (0 = locked). One-time badges are 0 or 1.
    let count: Int
    let earnedAt: Date?
    /// 0…1 toward the next earn, for locked badges with a measurable goal.
    let progress: Double
    let progressText: String?
    var id: String { definition.id }
    var earned: Bool { count > 0 }
}

struct ProgressionState: Equatable, Sendable {
    let events: [XPEvent]
    let totalXP: Int
    let level: Int
    let levelFloorXP: Int
    let nextLevelXP: Int
    let rank: BoxRank
    let nextRank: BoxRank?
    let badges: [BadgeState]
    var levelProgress: Double { Double(totalXP - levelFloorXP) / Double(max(1, nextLevelXP - levelFloorXP)) }
    var xpToNextLevel: Int { max(0, nextLevelXP - totalXP) }
    func xp(on day: Date, calendar: Calendar = .current) -> Int { events.filter { calendar.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.amount } }
    func xp(forSession id: UUID) -> Int { events.filter { $0.sessionID == id }.reduce(0) { $0 + $1.amount } }
}

enum Progression {
    // MARK: Rules

    enum Rules {
        static let minutesXP = 10              // per minute of timed work
        static let sessionCap = 300            // minutes XP per session
        static let minimumWorkSeconds = 60.0
        static let planSessionBonus = 150
        static let trainingDayBonus = 40       // first training of a day
        static let mealXP = 10, mealsPerDay = 3, fullFuelDayBonus = 20
        static let proteinDayBonus = 25, waterDayBonus = 15
        static let perfectWeekBonus = 500
        static let badgeBonus = 100
        static let streakMilestones: [(days: Int, xp: Int)] = [(3, 75), (7, 200), (14, 400), (30, 1000), (60, 2000), (100, 4000)]
        static let detectionCheckXP = 50
        static func sparringXP(_ summary: SparringSummary) -> Int {
            if summary.configuration.mode == .check { return detectionCheckXP }
            let multiplier = summary.configuration.difficulty.xpMultiplier
            let base = 60 + min(400, summary.score / 15) + summary.maxStreak * 2
            return Int((Double(base) * multiplier).rounded())
        }
    }

    // MARK: Levels and ranks

    /// Total XP needed to reach `level` (level 1 = 0, 2 = 100, 3 = 300, 5 = 1,000, 10 = 4,500, 20 = 19,000).
    static func xpRequired(forLevel level: Int) -> Int { 50 * (level - 1) * level }
    static func level(forXP xp: Int) -> Int {
        var level = 1
        while xpRequired(forLevel: level + 1) <= xp { level += 1 }
        return level
    }

    static let ranks: [BoxRank] = [
        .init(index: 0, title: "Rookie", minimumLevel: 1, symbol: "figure.boxing"),
        .init(index: 1, title: "Novice", minimumLevel: 3, symbol: "hand.raised.fill"),
        .init(index: 2, title: "Prospect", minimumLevel: 5, symbol: "bolt.fill"),
        .init(index: 3, title: "Amateur", minimumLevel: 8, symbol: "flame.fill"),
        .init(index: 4, title: "Golden Gloves", minimumLevel: 11, symbol: "star.fill"),
        .init(index: 5, title: "Contender", minimumLevel: 14, symbol: "shield.lefthalf.filled"),
        .init(index: 6, title: "Pro", minimumLevel: 17, symbol: "medal.fill"),
        .init(index: 7, title: "Ranked Pro", minimumLevel: 20, symbol: "chart.line.uptrend.xyaxis"),
        .init(index: 8, title: "Title Challenger", minimumLevel: 24, symbol: "flag.checkered"),
        .init(index: 9, title: "Champion", minimumLevel: 28, symbol: "crown.fill"),
        .init(index: 10, title: "Undisputed", minimumLevel: 33, symbol: "trophy.fill"),
        .init(index: 11, title: "Hall of Fame", minimumLevel: 40, symbol: "building.columns.fill")
    ]
    static func rank(forLevel level: Int) -> BoxRank { ranks.last { $0.minimumLevel <= level } ?? ranks[0] }

    // MARK: Badges

    static let badges: [BadgeDefinition] = [
        .init(id: "first-bell", title: "First Bell", detail: "Save your first training session.", symbol: "bell.fill", group: .training, repeatable: false),
        .init(id: "sessions-10", title: "Ten Rounds", detail: "Save 10 training sessions.", symbol: "10.circle.fill", group: .training, repeatable: false),
        .init(id: "sessions-50", title: "Fifty Strong", detail: "Save 50 training sessions.", symbol: "50.circle.fill", group: .training, repeatable: false),
        .init(id: "sessions-100", title: "Centurion", detail: "Save 100 training sessions.", symbol: "rosette", group: .training, repeatable: false),
        .init(id: "hours-5", title: "Five Hours In", detail: "Bank 5 hours of timed work.", symbol: "clock.fill", group: .training, repeatable: false),
        .init(id: "hours-25", title: "Gym Rat", detail: "Bank 25 hours of timed work.", symbol: "hourglass", group: .training, repeatable: false),
        .init(id: "streak-7", title: "Week Warrior", detail: "Train 7 days in a row. Earn it again with every new 7-day run.", symbol: "flame.fill", group: .training, repeatable: true),
        .init(id: "streak-30", title: "Iron Month", detail: "Train 30 days in a row.", symbol: "flame.circle.fill", group: .training, repeatable: true),
        .init(id: "perfect-week", title: "Perfect Week", detail: "Complete every planned training session in a program week.", symbol: "calendar.badge.checkmark", group: .training, repeatable: true),
        .init(id: "first-fight", title: "First Fight", detail: "Finish your first sparring session.", symbol: "figure.boxing", group: .sparring, repeatable: false),
        .init(id: "score-3000", title: "Heavy Hitter", detail: "Score 3,000 in one sparring session.", symbol: "bolt.fill", group: .sparring, repeatable: false),
        .init(id: "score-10000", title: "Knockout Artist", detail: "Score 10,000 in one sparring session.", symbol: "bolt.circle.fill", group: .sparring, repeatable: false),
        .init(id: "streak-25", title: "In the Zone", detail: "Hit a 25-move streak in sparring.", symbol: "sparkles", group: .sparring, repeatable: false),
        .init(id: "streak-50", title: "Unstoppable", detail: "Hit a 50-move streak in sparring.", symbol: "tornado", group: .sparring, repeatable: false),
        .init(id: "untouchable", title: "Untouchable", detail: "Dodge every attack in a sparring session (8 or more slips and ducks).", symbol: "shield.fill", group: .sparring, repeatable: true),
        .init(id: "full-arsenal", title: "Full Arsenal", detail: "Land all nine moves in one sparring session.", symbol: "square.grid.3x3.fill", group: .sparring, repeatable: false),
        .init(id: "champion-finish", title: "Championship Rounds", detail: "Finish a Champion-difficulty fight without being knocked out.", symbol: "crown.fill", group: .sparring, repeatable: true),
        .init(id: "calibrated", title: "Dialed In", detail: "Complete a Detection check.", symbol: "scope", group: .sparring, repeatable: false),
        .init(id: "fuel-7", title: "Fueled Up", detail: "Log meals on 7 days in a row.", symbol: "fork.knife", group: .fuel, repeatable: true),
        .init(id: "protein-5", title: "Protein Pro", detail: "Hit your protein target on 5 days.", symbol: "bolt.heart.fill", group: .fuel, repeatable: false),
        .init(id: "hydrated-7", title: "Hydrated", detail: "Hit your water target on 7 days.", symbol: "drop.fill", group: .fuel, repeatable: false)
    ]

    // MARK: Ledger

    static func compute(_ snapshot: ProgressionSnapshot) -> ProgressionState {
        let cal = snapshot.calendar
        var events: [XPEvent] = []
        func day(_ date: Date) -> Date { cal.startOfDay(for: date) }
        func key(_ date: Date) -> String { let c = cal.dateComponents([.year, .month, .day], from: date); return "\(c.year!)-\(c.month!)-\(c.day!)" }

        // Sessions and sparring.
        let sessions = snapshot.sessions.filter { $0.workSeconds >= Rules.minimumWorkSeconds || ($0.sparring?.attempts ?? 0) > 0 }.sorted { $0.date < $1.date }
        for session in sessions {
            if let sparring = session.sparring {
                let title = sparring.configuration.mode == .check ? "Detection check" : "Sparring · \(sparring.score) pts"
                events.append(.init(id: "session-\(session.id)", date: session.date, amount: Rules.sparringXP(sparring), title: title, category: .sparring, sessionID: session.id))
            } else {
                let xp = min(Rules.sessionCap, Int(session.workSeconds / 60) * Rules.minutesXP)
                if xp > 0 { events.append(.init(id: "session-\(session.id)", date: session.date, amount: xp, title: "Training · \(Int(session.workSeconds / 60)) min", category: .training, sessionID: session.id)) }
            }
        }
        for workout in snapshot.workouts {
            events.append(.init(id: "workout-\(workout.id)", date: workout.date, amount: 80, title: "Workout logged", category: .training))
        }
        // Completed planned sessions.
        for assignment in snapshot.assignments where assignment.isTraining && assignment.isComplete {
            let when = sessions.first { $0.assignmentID == assignment.id }?.date ?? assignment.date
            events.append(.init(id: "plan-\(assignment.id)", date: when, amount: Rules.planSessionBonus, title: "Planned session complete", category: .plan,
                                sessionID: sessions.first { $0.assignmentID == assignment.id }?.id))
        }
        // First training of each day.
        let trainingDates = sessions.map(\.date) + snapshot.workouts.map(\.date)
        let trainingDays = Set(trainingDates.map(day))
        for d in trainingDays {
            let first = trainingDates.filter { cal.isDate($0, inSameDayAs: d) }.min() ?? d
            events.append(.init(id: "day-\(key(d))", date: first, amount: Rules.trainingDayBonus, title: "Trained today", category: .training))
        }
        // Streak milestones: each time a run reaches 3, 7, 14… days.
        var streakRuns: [(start: Date, length: Int)] = []
        var run = 0, runStart: Date?
        for d in trainingDays.sorted() {
            if let previous = runStart.flatMap({ cal.date(byAdding: .day, value: run, to: $0) }), cal.isDate(previous, inSameDayAs: d) { run += 1 }
            else { if let s = runStart { streakRuns.append((s, run)) }; runStart = d; run = 1 }
            if let start = runStart, let milestone = Rules.streakMilestones.first(where: { $0.days == run }) {
                events.append(.init(id: "streak-\(milestone.days)-\(key(start))", date: d, amount: milestone.xp, title: "\(milestone.days)-day streak", category: .streak))
            }
        }
        if let s = runStart { streakRuns.append((s, run)) }
        // Fuel.
        let mealsByDay = Dictionary(grouping: snapshot.meals) { day($0.date) }
        var proteinDays = 0, fuelRuns: [Int] = [], fuelRun = 0, previousFuelDay: Date?
        for (d, meals) in mealsByDay.sorted(by: { $0.key < $1.key }) {
            for meal in meals.sorted(by: { $0.date < $1.date }).prefix(Rules.mealsPerDay) {
                events.append(.init(id: "meal-\(meal.id)", date: meal.date, amount: Rules.mealXP, title: "Meal logged", category: .fuel))
            }
            if meals.count >= Rules.mealsPerDay { events.append(.init(id: "fuelday-\(key(d))", date: d, amount: Rules.fullFuelDayBonus, title: "Full day of fuel logged", category: .fuel)) }
            if snapshot.proteinTarget > 0, meals.reduce(0, { $0 + $1.protein }) >= snapshot.proteinTarget {
                proteinDays += 1
                events.append(.init(id: "protein-\(key(d))", date: d, amount: Rules.proteinDayBonus, title: "Protein target hit", category: .fuel))
            }
            if let p = previousFuelDay, let next = cal.date(byAdding: .day, value: 1, to: p), cal.isDate(next, inSameDayAs: d) { fuelRun += 1 } else { if fuelRun > 0 { fuelRuns.append(fuelRun) }; fuelRun = 1 }
            previousFuelDay = d
        }
        if fuelRun > 0 { fuelRuns.append(fuelRun) }
        var waterDays = 0
        if snapshot.waterTarget > 0 {
            for (d, entries) in Dictionary(grouping: snapshot.water, by: { day($0.date) }) where entries.reduce(0, { $0 + $1.millilitres }) >= snapshot.waterTarget {
                waterDays += 1
                events.append(.init(id: "water-\(key(d))", date: d, amount: Rules.waterDayBonus, title: "Water target hit", category: .fuel))
            }
        }
        // Perfect program weeks.
        var perfectWeeks: [Date] = []
        for (planID, items) in Dictionary(grouping: snapshot.assignments.filter { $0.planID != nil }, by: { $0.planID! }) {
            let training = items.filter(\.isTraining)
            guard !training.isEmpty, training.allSatisfy(\.isComplete), let last = items.map(\.date).max() else { continue }
            perfectWeeks.append(last)
            events.append(.init(id: "week-\(planID)", date: last, amount: Rules.perfectWeekBonus, title: "Perfect program week", category: .plan))
        }

        // Badges.
        let sparring = sessions.compactMap { s in s.sparring.map { (s, $0) } }
        let arcade = sparring.filter { $0.1.configuration.mode == .arcade }
        let totalHours = sessions.reduce(0) { $0 + $1.workSeconds } / 3600
        func firstDate(_ items: [Date]) -> Date? { items.min() }
        func nth(_ n: Int, _ dates: [Date]) -> Date? { dates.count >= n ? dates.sorted()[n - 1] : nil }
        let sessionDates = sessions.map(\.date)
        var states: [BadgeState] = []
        func add(_ id: String, count: Int, at: Date?, progress: Double = 0, text: String? = nil) {
            guard let definition = badges.first(where: { $0.id == id }) else { return }
            states.append(.init(definition: definition, count: count, earnedAt: count > 0 ? at : nil, progress: count > 0 ? 1 : min(1, progress), progressText: count > 0 ? nil : text))
        }
        add("first-bell", count: sessions.isEmpty ? 0 : 1, at: firstDate(sessionDates))
        for n in [10, 50, 100] { add("sessions-\(n)", count: sessions.count >= n ? 1 : 0, at: nth(n, sessionDates), progress: Double(sessions.count) / Double(n), text: "\(sessions.count)/\(n)") }
        for h in [5, 25] { add("hours-\(h)", count: totalHours >= Double(h) ? 1 : 0, at: sessions.last?.date, progress: totalHours / Double(h), text: String(format: "%.1f/%d h", totalHours, h)) }
        let longest = streakRuns.map(\.length).max() ?? 0
        add("streak-7", count: streakRuns.filter { $0.length >= 7 }.count, at: streakRuns.last { $0.length >= 7 }.flatMap { cal.date(byAdding: .day, value: 6, to: $0.start) },
            progress: Double(min(longest, 7)) / 7, text: "Best \(longest)/7 days")
        add("streak-30", count: streakRuns.filter { $0.length >= 30 }.count, at: streakRuns.last { $0.length >= 30 }.flatMap { cal.date(byAdding: .day, value: 29, to: $0.start) },
            progress: Double(min(longest, 30)) / 30, text: "Best \(longest)/30 days")
        add("perfect-week", count: perfectWeeks.count, at: perfectWeeks.max())
        add("first-fight", count: arcade.isEmpty ? 0 : 1, at: arcade.first?.0.date)
        let bestScore = arcade.map(\.1.score).max() ?? 0
        for target in [3000, 10000] {
            add("score-\(target)", count: bestScore >= target ? 1 : 0, at: arcade.first { $0.1.score >= target }?.0.date, progress: Double(bestScore) / Double(target), text: "Best \(bestScore)")
        }
        let bestStreak = arcade.map(\.1.maxStreak).max() ?? 0
        for target in [25, 50] {
            add("streak-\(target)", count: bestStreak >= target ? 1 : 0, at: arcade.first { $0.1.maxStreak >= target }?.0.date, progress: Double(bestStreak) / Double(target), text: "Best \(bestStreak)")
        }
        func dodges(_ s: SparringSummary) -> (asked: Int, hit: Int) {
            s.moves.filter { $0.key.hasPrefix("Slip") || $0.key == "Duck" }.reduce((0, 0)) { ($0.0 + $1.value.asked, $0.1 + $1.value.hit) }
        }
        let clean = arcade.filter { let d = dodges($0.1); return d.asked >= 8 && d.hit == d.asked }
        add("untouchable", count: clean.count, at: clean.last?.0.date)
        let arsenal = arcade.first { $0.1.moves.values.filter { $0.hit > 0 }.count >= 9 }
        add("full-arsenal", count: arsenal == nil ? 0 : 1, at: arsenal?.0.date)
        let champs = arcade.filter { [.champion, .undisputed].contains($0.1.configuration.difficulty) && !$0.1.knockedOut && $0.1.roundsCompleted >= $0.1.configuration.rounds }
        add("champion-finish", count: champs.count, at: champs.last?.0.date)
        let checks = sparring.filter { $0.1.configuration.mode == .check }
        add("calibrated", count: checks.isEmpty ? 0 : 1, at: checks.first?.0.date)
        let longestFuel = fuelRuns.max() ?? 0
        add("fuel-7", count: fuelRuns.filter { $0 >= 7 }.count, at: previousFuelDay, progress: Double(min(longestFuel, 7)) / 7, text: "Best \(longestFuel)/7 days")
        add("protein-5", count: proteinDays >= 5 ? 1 : 0, at: previousFuelDay, progress: Double(proteinDays) / 5, text: "\(proteinDays)/5 days")
        add("hydrated-7", count: waterDays >= 7 ? 1 : 0, at: snapshot.water.map(\.date).max(), progress: Double(waterDays) / 7, text: "\(waterDays)/7 days")

        for badge in states where badge.earned {
            events.append(.init(id: "badge-\(badge.id)-\(badge.count)", date: badge.earnedAt ?? .now, amount: Rules.badgeBonus * badge.count,
                                title: "Badge: \(badge.definition.title)", category: .badge))
        }

        let total = events.reduce(0) { $0 + $1.amount }
        let level = level(forXP: total)
        let rank = rank(forLevel: level)
        return .init(events: events.sorted { $0.date > $1.date }, totalXP: total, level: level,
                     levelFloorXP: xpRequired(forLevel: level), nextLevelXP: xpRequired(forLevel: level + 1),
                     rank: rank, nextRank: ranks.first { $0.index == rank.index + 1 }, badges: states)
    }
}
