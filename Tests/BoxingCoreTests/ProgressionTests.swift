import Foundation
import Testing
@testable import BoxingCore

struct ProgressionTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    func day(_ n: Int, hour: Int = 18) -> Date { cal.date(from: DateComponents(year: 2026, month: 10, day: n, hour: hour))! }
    func session(_ n: Int, minutes: Double = 20, sparring: SparringSummary? = nil, assignment: UUID? = nil) -> ProgressionSnapshot.Session {
        .init(id: UUID(), date: day(n), workSeconds: minutes * 60, finished: true, assignmentID: assignment, sparring: sparring)
    }
    func snapshot(_ build: (inout ProgressionSnapshot) -> Void) -> ProgressionState {
        var s = ProgressionSnapshot(); s.calendar = cal; build(&s); return Progression.compute(s)
    }

    @Test func newUsersStartAtLevelOneRookieWithNoXP() {
        let state = snapshot { _ in }
        #expect(state.totalXP == 0 && state.level == 1 && state.rank.title == "Rookie" && state.badges.allSatisfy { !$0.earned })
    }

    @Test func levelCurveAndRanks() {
        #expect(Progression.xpRequired(forLevel: 2) == 100 && Progression.xpRequired(forLevel: 5) == 1000 && Progression.xpRequired(forLevel: 10) == 4500)
        #expect(Progression.level(forXP: 99) == 1 && Progression.level(forXP: 100) == 2 && Progression.level(forXP: 4499) == 9 && Progression.level(forXP: 4500) == 10)
        #expect(Progression.rank(forLevel: 1).title == "Rookie" && Progression.rank(forLevel: 14).title == "Contender" && Progression.rank(forLevel: 99).title == "Hall of Fame")
        #expect(zip(Progression.ranks, Progression.ranks.dropFirst()).allSatisfy { $0.minimumLevel < $1.minimumLevel })
    }

    @Test func trainingXPIsMinutesCappedPlusOneDailyBonus() {
        let state = snapshot { $0.sessions = [session(1, minutes: 20), session(1, minutes: 90)] }
        // 200 (20 min) + 300 (cap) + 40 first-training-of-the-day, once; plus the First Bell badge.
        #expect(state.events.filter { $0.category == .training }.reduce(0) { $0 + $1.amount } == 540)
        #expect(state.badges.first { $0.id == "first-bell" }?.earned == true)
        #expect(snapshot { $0.sessions = [session(1, minutes: 0.5)] }.totalXP == 0) // under a minute earns nothing
    }

    @Test func plannedSessionsAndPerfectWeeksEarnBonuses() {
        let plan = UUID(), a = UUID(), b = UUID(), rest = UUID()
        let state = snapshot {
            $0.sessions = [session(1, assignment: a), session(3, assignment: b)]
            $0.assignments = [.init(id: a, date: day(1), planID: plan, isTraining: true, isComplete: true),
                              .init(id: b, date: day(3), planID: plan, isTraining: true, isComplete: true),
                              .init(id: rest, date: day(2), planID: plan, isTraining: false, isComplete: false)]
        }
        #expect(state.events.filter { $0.id.hasPrefix("plan-") }.count == 2)
        #expect(state.events.contains { $0.id == "week-\(plan)" && $0.amount == 500 })
        #expect(state.badges.first { $0.id == "perfect-week" }?.count == 1)
        let unfinished = snapshot { $0.assignments = [.init(id: a, date: day(1), planID: plan, isTraining: true, isComplete: false)] }
        #expect(!unfinished.events.contains { $0.id.hasPrefix("week-") })
    }

    @Test func streakMilestonesRepeatPerRunAndBadgesCountRuns() {
        let state = snapshot { s in s.sessions = (1...7).map { session($0) } + (10...16).map { session($0) } }
        #expect(state.events.filter { $0.id.hasPrefix("streak-7-") }.count == 2)
        #expect(state.events.filter { $0.id.hasPrefix("streak-3-") }.count == 2)
        #expect(state.badges.first { $0.id == "streak-7" }?.count == 2)
        let broken = snapshot { s in s.sessions = [1, 2, 4, 5, 6].map { session($0) } }
        #expect(broken.events.filter { $0.category == .streak }.count == 1) // only the 4-5-6 run reaches 3
    }

    @Test func fuelXPIsCappedPerDayAndTargetsMustBeMet() {
        let state = snapshot { s in
            s.meals = (0..<5).map { .init(id: UUID(), date: day(1, hour: 8 + $0), protein: 40) }
            s.proteinTarget = 150; s.water = [.init(date: day(1), millilitres: 1500)]; s.waterTarget = 2000
        }
        #expect(state.events.filter { $0.id.hasPrefix("meal-") }.count == 3)
        #expect(state.events.contains { $0.id.hasPrefix("fuelday-") } && state.events.contains { $0.id.hasPrefix("protein-") })
        #expect(!state.events.contains { $0.id.hasPrefix("water-") })
    }

    @Test func sparringXPScalesWithScoreAndDifficultyAndUnlocksBadges() {
        func summary(_ difficulty: SparringConfiguration.Difficulty, score: Int, streak: Int, mode: SparringConfiguration.Mode = .arcade) -> SparringSummary {
            var s = SparringSummary(configuration: .init(difficulty: difficulty, mode: mode, rounds: 1)); s.score = score; s.maxStreak = streak; s.attempts = 20; s.hits = 18; s.roundsCompleted = 1
            s.moves = ["Duck": .init(asked: 4, hit: 4), "Slip left": .init(asked: 3, hit: 3), "Slip right": .init(asked: 2, hit: 2)]
            return s
        }
        let rookie = Progression.Rules.sparringXP(summary(.rookie, score: 3000, streak: 10))
        let champion = Progression.Rules.sparringXP(summary(.champion, score: 3000, streak: 10))
        #expect(champion > rookie && rookie == 60 + 200 + 20)
        #expect(Progression.Rules.sparringXP(summary(.contender, score: 9_999_999, streak: 0)) == Int((Double(60 + 400) * 1.25).rounded()))
        let state = snapshot { $0.sessions = [session(1, minutes: 3, sparring: summary(.champion, score: 10_500, streak: 30)), session(2, minutes: 1, sparring: summary(.rookie, score: 0, streak: 0, mode: .check))] }
        let earned = Set(state.badges.filter(\.earned).map(\.id))
        #expect(earned.isSuperset(of: ["first-fight", "score-3000", "score-10000", "streak-25", "untouchable", "champion-finish", "calibrated"]))
        #expect(!earned.contains("streak-50") && !earned.contains("full-arsenal"))
        #expect(state.badges.first { $0.id == "streak-50" }?.progressText == "Best 30")
    }

    @Test func everyAwardHasAUniqueStableIDSoNothingDoubleCounts() {
        let fixed = session(1)
        let a = snapshot { $0.sessions = [fixed, session(2), session(3)] }
        let b = snapshot { $0.sessions = [fixed, session(2), session(3)] }
        #expect(Set(a.events.map(\.id)).count == a.events.count)
        #expect(a.events.first { $0.id == "session-\(fixed.id)" }?.amount == b.events.first { $0.id == "session-\(fixed.id)" }?.amount)
        #expect(a.xp(forSession: fixed.id) == 200)
    }
}
