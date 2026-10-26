import Foundation
import Testing
@testable import BoxingCore

struct AdaptiveSummaryTests {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
    var now: Date { Date(timeIntervalSince1970: 1_800_000_000) }
    func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now))!.addingTimeInterval(3600 * 10) }

    func guided(_ offset: Int, effort: Int?, activity: String = "lead-hook-v1") -> SessionRecord {
        let session = GuidedSession(title: "S", type: .technique, activities: [.init(id: "a", activityID: activity, mode: .shadowboxing, sets: 1, reps: 0, workSeconds: 60, restSeconds: 0)])
        return SessionRecord(id: UUID(), date: day(offset), focus: .mixed, activeSeconds: 600, workSeconds: 600, completedRounds: 0, skippedBlocks: 1, issuedCues: 0,
                             finished: false, guided: GuidedSummary(execution: GuidedExecution(session: session), feedback: nil, effort: effort))
    }
    func fight(_ offset: Int, hook: (Int, Int), jab: (Int, Int)) -> SessionRecord {
        var s = SparringSummary(configuration: .init(difficulty: .contender), score: 3000, maxStreak: 12, hits: hook.1 + jab.1, attempts: hook.0 + jab.0)
        s.moves = ["Left hook": .init(asked: hook.0, hit: hook.1), "Jab": .init(asked: jab.0, hit: jab.1)]
        return SessionRecord(id: UUID(), date: day(offset), focus: .mixed, activeSeconds: 120, workSeconds: 120, completedRounds: 2, skippedBlocks: 0, issuedCues: 0, finished: true, sparring: s)
    }
    func input(history: [SessionRecord], plan: [AdaptiveSummary.PlanDay], level: Int = 6) -> AdaptiveSummary.Input {
        var snapshot = ProgressionSnapshot()
        snapshot.sessions = (0..<level).map { .init(id: UUID(), date: day(-30 - $0), workSeconds: 1800, finished: true, assignmentID: nil, sparring: nil) }
        let progression = Progression.compute(snapshot)
        return .init(now: now, calendar: cal, history: history, plan: plan, progression: progression, unlocks: RankUnlocks.state(level: level, sparring: []))
    }

    @Test func noHistoryStartsConservatively() {
        let s = AdaptiveSummary.build(input(history: [], plan: []))
        #expect(s.coachNotes == ["No training history yet: start conservatively with fundamentals and short sessions, then adapt next week."])
        #expect(s.weeks.count == 4 && s.adherence == nil)
    }

    @Test func missedSessionsHardEffortSkipsAndWeakMovesBecomeRules() throws {
        let plan = (1...8).map { AdaptiveSummary.PlanDay(date: day(-$0 * 1), isTraining: true, completion: $0 <= 2, partial: $0 == 3) }
        let history = [guided(-1, effort: 4), guided(-2, effort: 3), guided(-3, effort: 4),
                       fight(-4, hook: (10, 4), jab: (12, 11)), fight(-9, hook: (6, 1), jab: (8, 7))]
        let s = AdaptiveSummary.build(input(history: history, plan: plan))
        #expect(s.adherence == 0.25)
        #expect(s.coachNotes.contains { $0.hasPrefix("Adherence 25%") })
        #expect(s.coachNotes.contains { $0.hasPrefix("Sessions felt too hard") })
        #expect(s.coachNotes.contains { $0.contains("Lead hook (lead-hook-v1) was skipped 3 times") })
        let hook = try #require(s.moves.first)
        #expect(hook.move == "Left hook" && hook.asked == 16 && hook.drillID == "lead-hook-v1")
        #expect(s.coachNotes.contains { $0.contains("Left hook is 31%") || $0.contains("Left hook is \(Int(hook.accuracy * 100))%") })
        #expect(s.coachNotes.contains { $0.hasPrefix("Jab is strong") })
        #expect(s.effort?.hasPrefix("too hard") == true)
        #expect(s.weeks.last?.completedSessions == 2)
    }

    @Test func consistentEasyWeeksProgress() {
        let plan = (1...6).map { AdaptiveSummary.PlanDay(date: day(-$0 * 2), isTraining: true, completion: true, partial: false) }
        let history = (1...4).map { guided(-$0 * 2, effort: 1, activity: "jab-reset-v1") }
        let s = AdaptiveSummary.build(input(history: history, plan: plan))
        #expect(s.coachNotes.contains { $0.hasPrefix("Adherence 100%") })
        #expect(s.coachNotes.contains { $0.hasPrefix("Sessions felt too easy") })
        #expect(s.coachNotes.contains { $0.hasPrefix("No camera sparring") })
    }

    @Test func drillMappingFollowsStance() {
        #expect(AdaptiveSummary.drill(forMove: "Left hook", stance: .southpaw) == "rear-hook-v1")
        #expect(AdaptiveSummary.drill(forMove: "Right uppercut", stance: .southpaw) == "lead-uppercut-v1")
        #expect(AdaptiveSummary.drill(forMove: "Duck", stance: .orthodox) == "duck-v1")
    }
}
