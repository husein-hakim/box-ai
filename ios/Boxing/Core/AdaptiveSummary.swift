import Foundation

/// The athlete's recent training, digested for the program generator: weekly
/// adherence and effort, which activities get done or skipped, per-move camera
/// accuracy and its trend, progression, nutrition logging, and the last plan.
/// `coachNotes` are deterministic adaptation rules the model must follow, so the
/// next week responds to the data instead of being a generic refresh.
struct AdaptiveSummary: Codable, Equatable, Sendable {
    struct Week: Codable, Equatable, Sendable {
        var start: String
        var plannedSessions: Int
        var completedSessions: Int
        var partialSessions: Int
        var missedSessions: Int
        var trainedMinutes: Int
        var sparringSessions: Int
        var averageEffort: Double?
    }
    struct ActivityRecord: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var completed: Int
        var partial: Int
        var skipped: Int
    }
    struct MoveSkill: Codable, Equatable, Sendable {
        var move: String
        var asked: Int
        var hit: Int
        var accuracy: Double
        /// Accuracy change from the earlier half of recent sessions to the later half.
        var trend: Double?
        var drillID: String?
    }
    var weeks: [Week]
    var adherence: Double?
    var effort: String?
    var activities: [ActivityRecord]
    var moves: [MoveSkill]
    var bestSparringScores: [String: Int]
    var level: Int
    var rank: String
    var streakDays: Int
    var unlockedDifficulties: [String]
    var nutrition: String?
    var lastPlan: String?
    var coachNotes: [String]

    /// One planned day, flattened from the stored plan.
    struct PlanDay: Sendable {
        var date: Date
        var isTraining: Bool
        var completion: Bool
        var partial: Bool
    }
    struct Input: Sendable {
        var now = Date()
        var calendar = Calendar.current
        var history: [SessionRecord] = []
        var plan: [PlanDay] = []
        var mealDays: Set<Date> = []
        var proteinHitDays: Int = 0
        var progression: ProgressionState
        var unlocks: UnlockState
        var stance: BoxMaxxingJudge.Stance = .orthodox
        var lastPlan: (title: String, progression: String)? = nil
    }

    static func build(_ input: Input) -> AdaptiveSummary {
        let cal = input.calendar
        let today = cal.startOfDay(for: input.now)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.calendar = cal; formatter.timeZone = cal.timeZone; formatter.dateFormat = "yyyy-MM-dd"

        // Weeks: four 7-day windows ending yesterday, oldest first.
        var weeks: [Week] = []
        for w in (0..<4).reversed() {
            guard let end = cal.date(byAdding: .day, value: -7 * w, to: today), let start = cal.date(byAdding: .day, value: -7, to: end) else { continue }
            let sessions = input.history.filter { $0.date >= start && $0.date < end }
            let planned = input.plan.filter { $0.isTraining && $0.date >= start && $0.date < end }
            let efforts = sessions.compactMap { $0.guided?.effort }
            weeks.append(Week(start: formatter.string(from: start), plannedSessions: planned.count,
                              completedSessions: planned.filter(\.completion).count, partialSessions: planned.filter { !$0.completion && $0.partial }.count,
                              missedSessions: planned.filter { !$0.completion && !$0.partial }.count,
                              trainedMinutes: Int(sessions.reduce(0) { $0 + $1.workSeconds } / 60), sparringSessions: sessions.filter { $0.sparring != nil }.count,
                              averageEffort: efforts.isEmpty ? nil : Double(efforts.reduce(0, +)) / Double(efforts.count)))
        }
        let recentWeeks = weeks.suffix(2)
        let planned = recentWeeks.reduce(0) { $0 + $1.plannedSessions }
        let adherence = planned >= 2 ? Double(recentWeeks.reduce(0) { $0 + $1.completedSessions }) / Double(planned) : nil

        let since = cal.date(byAdding: .day, value: -28, to: today) ?? today
        let recent = input.history.filter { $0.date >= since }
        let efforts = recent.compactMap { $0.guided?.effort }
        let averageEffort = efforts.count >= 2 ? Double(efforts.reduce(0, +)) / Double(efforts.count) : nil
        let effortText = averageEffort.map { a in
            let label = a < 1.6 ? "mostly too easy" : a < 2.5 ? "about right" : a < 3.3 ? "hard" : "too hard"
            return "\(label) (average \(String(format: "%.1f", a)) on 1 too easy – 4 too hard, \(efforts.count) ratings)"
        }

        // Activities: what gets done, what gets skipped.
        var table: [String: ActivityRecord] = [:]
        for record in recent {
            guard let execution = record.guided?.execution else { continue }
            for (i, item) in execution.session.activities.enumerated() {
                guard let activity = ActivityCatalog.find(item.activityID), ![.warmup, .cooldown, .mobility].contains(activity.kind) else { continue }
                var row = table[item.activityID] ?? .init(id: item.activityID, title: activity.title, completed: 0, partial: 0, skipped: 0)
                switch execution.outcome(at: i) {
                case .completed: row.completed += 1
                case .partial: row.partial += 1
                case .skipped, .notStarted: row.skipped += 1
                }
                table[item.activityID] = row
            }
        }
        let activities = table.values.sorted { ($0.skipped, $0.completed) > ($1.skipped, $1.completed) }.prefix(10).map { $0 }

        // Moves: accuracy across sparring, drills and detection checks.
        let fights = recent.compactMap(\.sparring)
        var moveTotals: [String: (asked: Int, hit: Int)] = [:]
        for fight in fights { for (name, stats) in fight.moves { moveTotals[name, default: (0, 0)].asked += stats.asked; moveTotals[name, default: (0, 0)].hit += stats.hit } }
        let half = fights.count / 2
        func accuracy(_ name: String, _ slice: ArraySlice<SparringSummary>) -> Double? {
            let a = slice.reduce(0) { $0 + ($1.moves[name]?.asked ?? 0) }, h = slice.reduce(0) { $0 + ($1.moves[name]?.hit ?? 0) }
            return a >= 4 ? Double(h) / Double(a) : nil
        }
        let ordered = recent.filter { $0.sparring != nil }.sorted { $0.date < $1.date }.compactMap(\.sparring)
        let moves = moveTotals.filter { $0.value.asked >= 4 }.map { name, t in
            let early = half >= 1 ? accuracy(name, ordered.prefix(half)) : nil, late = half >= 1 ? accuracy(name, ordered.suffix(ordered.count - half)) : nil
            return MoveSkill(move: name, asked: t.asked, hit: t.hit, accuracy: Double(t.hit) / Double(t.asked),
                             trend: early.flatMap { e in late.map { $0 - e } }, drillID: drill(forMove: name, stance: input.stance))
        }.sorted { $0.accuracy < $1.accuracy }

        var best: [String: Int] = [:]
        for fight in input.history.compactMap(\.sparring) where fight.configuration.mode == .arcade {
            best[fight.configuration.difficulty.rawValue] = max(best[fight.configuration.difficulty.rawValue] ?? 0, fight.score)
        }

        let fortnight = cal.date(byAdding: .day, value: -14, to: today) ?? today
        let loggedDays = input.mealDays.filter { $0 >= fortnight && $0 < today }.count
        let nutrition = loggedDays > 0 ? "Logged meals on \(loggedDays) of the last 14 days; protein target hit on \(input.proteinHitDays)." : nil

        var summary = AdaptiveSummary(weeks: weeks, adherence: adherence, effort: effortText, activities: activities, moves: moves,
                                      bestSparringScores: best, level: input.progression.level, rank: input.progression.rank.title,
                                      streakDays: currentStreak(input.history, today: today, calendar: cal),
                                      unlockedDifficulties: input.unlocks.difficulties.map(\.rawValue), nutrition: nutrition,
                                      lastPlan: input.lastPlan.map { "\($0.title): \($0.progression.prefix(400))" }, coachNotes: [])
        summary.coachNotes = notes(summary, averageEffort: averageEffort, hasHistory: !recent.isEmpty)
        return summary
    }

    static func drill(forMove name: String, stance: BoxMaxxingJudge.Stance) -> String? {
        let n = name.lowercased()
        if n == "jab" { return "jab-reset-v1" }
        if n == "cross" { return "cross-reset-v1" }
        let lead = stance == .orthodox ? "left" : "right"
        if n.contains("hook") { return n.contains(lead) ? "lead-hook-v1" : "rear-hook-v1" }
        if n.contains("uppercut") { return n.contains(lead) ? "lead-uppercut-v1" : "rear-uppercut-v1" }
        if n.contains("slip") { return "slip-v1" }
        if n.contains("duck") { return "duck-v1" }
        return nil
    }

    private static func currentStreak(_ history: [SessionRecord], today: Date, calendar: Calendar) -> Int {
        let days = Set(history.map { calendar.startOfDay(for: $0.date) })
        var day = days.contains(today) ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        var count = 0
        while days.contains(day) { count += 1; day = calendar.date(byAdding: .day, value: -1, to: day)! }
        return count
    }

    /// Plain rules the generator must apply. Ordered by importance.
    static func notes(_ s: AdaptiveSummary, averageEffort: Double?, hasHistory: Bool) -> [String] {
        var out: [String] = []
        guard hasHistory else { return ["No training history yet: start conservatively with fundamentals and short sessions, then adapt next week."] }
        if let a = s.adherence {
            let pct = Int((a * 100).rounded())
            if a < 0.5 { out.append("Adherence \(pct)% over two weeks: cut the number of training days or shorten sessions so the week is achievable. Keep the session types they actually completed.") }
            else if a < 0.8 { out.append("Adherence \(pct)%: keep volume about the same and make the hardest day shorter.") }
            else { out.append("Adherence \(pct)%: they are consistent. Progress a little.") }
        }
        if let e = averageEffort {
            if e >= 3.3 { out.append("Sessions felt too hard: reduce total work about 20% and keep only one demanding day.") }
            else if e < 1.6 && (s.adherence ?? 1) >= 0.7 { out.append("Sessions felt too easy: add a set or move one or two blocks to the next difficulty or a longer combination.") }
        }
        for row in s.activities where row.skipped >= 2 && row.skipped > row.completed {
            out.append("\(row.title) (\(row.id)) was skipped \(row.skipped) times: replace it with an alternative for the same skill or shorten it.")
        }
        for move in s.moves.prefix(3) where move.accuracy < 0.6 && move.asked >= 8 {
            out.append("Camera accuracy on \(move.move) is \(Int(move.accuracy * 100))% over \(move.asked) attempts: add \(move.drillID ?? "a drill for it") (camera mode where supported) on two days.")
        }
        for move in s.moves.reversed().prefix(2) where move.accuracy >= 0.85 && move.asked >= 10 {
            out.append("\(move.move) is strong (\(Int(move.accuracy * 100))%): build it into longer combinations rather than isolated reps.")
        }
        if let improving = s.moves.first(where: { ($0.trend ?? 0) >= 0.15 }) {
            out.append("\(improving.move) improved by \(Int((improving.trend! * 100).rounded())) points recently: mention it in the progression and keep it in the week.")
        }
        if s.weeks.suffix(2).allSatisfy({ $0.sparringSessions == 0 }) && s.level >= 3 {
            out.append("No camera sparring in two weeks: include one short camera drill or sparring round.")
        }
        return Array(out.prefix(8))
    }
}
