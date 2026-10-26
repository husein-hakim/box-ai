import Foundation
import Testing
@testable import BoxingCore

struct SessionDebriefTests {
    func fight(_ date: Date, score: Int, hook: (Int, Int), jab: (Int, Int)) -> SessionRecord {
        var s = SparringSummary(configuration: .init(difficulty: .contender), score: score, maxStreak: 12, hits: hook.1 + jab.1, attempts: hook.0 + jab.0)
        s.moves = ["Left hook": .init(asked: hook.0, hit: hook.1), "Jab": .init(asked: jab.0, hit: jab.1)]
        return SessionRecord(id: UUID(), date: date, focus: .mixed, activeSeconds: 120, workSeconds: 180, completedRounds: 2, skippedBlocks: 0, issuedCues: 0, finished: true, sparring: s)
    }
    let next = GuidedSession(title: "Tuesday", type: .technique, activities: [
        .init(id: "w", activityID: "warm-march-v1", mode: .guided, sets: 1, reps: 0, workSeconds: 60, restSeconds: 0),
        .init(id: "j", activityID: "jab-reset-v1", mode: .shadowboxing, sets: 3, reps: 0, workSeconds: 60, restSeconds: 30),
        .init(id: "c", activityID: "cross-reset-v1", mode: .shadowboxing, sets: 3, reps: 0, workSeconds: 60, restSeconds: 30),
        .init(id: "d", activityID: "walk-reset-v1", mode: .guided, sets: 1, reps: 0, workSeconds: 60, restSeconds: 0)])
    func validate(_ s: GuidedSession) -> [String] { s.validationErrors(equipment: [], openSpace: false, difficulty: .intermediate, budget: 900) }

    @Test func sparringFactsCompareWithEarlierSessionsAndNameTheWeakMove() throws {
        let old = fight(.now.addingTimeInterval(-86_400 * 3), score: 3000, hook: (10, 5), jab: (10, 8))
        let new = fight(.now, score: 4200, hook: (12, 5), jab: (14, 13))
        let facts = SessionFacts.make(new, history: [new, old], stance: .orthodox)
        #expect(facts.kind == "sparring" && facts.previousBest == 3000)
        #expect(facts.weakest?.name == "Left hook" && facts.strongest?.name == "Jab")
        #expect(facts.text.contains("Left hook 5/12 (was 50%)"))
        let d = facts.autoDebrief(nextSession: "Tuesday")
        #expect(d.good.first?.title.contains("New best") == true)
        #expect(d.workOn.first?.title == "Left hook needs reps")
        #expect(d.next == "Next up: Tuesday." && d.source == "auto")
    }

    @Test func weakMoveAddsItsDrillToTheNextSessionWithinBudget() throws {
        let facts = SessionFacts.make(fight(.now, score: 2000, hook: (12, 4), jab: (12, 11)), history: [], stance: .orthodox)
        let adj = try #require(SessionAdjustment.propose(facts: facts, next: next, stance: .orthodox, validate: validate))
        #expect(adj.session.activities.contains { $0.activityID == "lead-hook-v1" })
        #expect(adj.session.activities.last?.activityID == "walk-reset-v1")
        #expect(validate(adj.session).isEmpty)
        #expect(adj.summary.contains("Lead hook"))
    }

    @Test func effortRatingsMakeTheNextSessionLighterOrHarder() throws {
        func guided(effort: Int) -> SessionFacts {
            var f = SessionFacts(kind: "guided", title: "x", minutes: 20); f.completed = 3; f.effort = effort; return f
        }
        let lighter = try #require(SessionAdjustment.propose(facts: guided(effort: 4), next: next, stance: .orthodox, validate: validate))
        #expect(lighter.session.activities.filter { ["jab-reset-v1", "cross-reset-v1"].contains($0.activityID) }.allSatisfy { $0.sets == 2 })
        let harder = try #require(SessionAdjustment.propose(facts: guided(effort: 1), next: next, stance: .orthodox, validate: validate))
        #expect(harder.session.activities.first { $0.activityID == "jab-reset-v1" }?.sets == 4)
        #expect(SessionAdjustment.propose(facts: guided(effort: 2), next: next, stance: .orthodox, validate: validate) == nil)
    }

    @Test func coachReplyIsCleaned() {
        let d = SessionDebrief(headline: "  Sharp work  ", good: [.init(title: "Jab", detail: "13 of 14")], workOn: [], next: "More hooks.", source: "coach").sanitized()
        #expect(d?.headline == "Sharp work")
        #expect(SessionDebrief(headline: "", good: [], workOn: [], next: "", source: "coach").sanitized() == nil)
    }
}

