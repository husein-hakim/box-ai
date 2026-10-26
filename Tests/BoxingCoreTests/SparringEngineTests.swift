import Foundation
import Testing
@testable import BoxingCore

struct SparringEngineTests {
    private func move(_ action: FightAction, at ms: Double) -> DetectedMove {
        .init(action: action, startMs: ms - 200, peakMs: ms, confidence: 0.9, source: .native)
    }
    /// Runs until the first beat is in play and returns it.
    private func firstBeat(_ engine: inout SparringEngine, from start: Double = 0) -> SparringBeat {
        var t = start
        while engine.active.isEmpty { t += 20; _ = engine.update(atMs: t) }
        return engine.active[0]
    }

    @Test func onTimeCorrectMoveScoresAndBuildsTheStreak() {
        var engine = SparringEngine(configuration: .init(difficulty: .contender), seed: 7)
        engine.start(atMs: 0)
        let beat = firstBeat(&engine)
        let events = engine.receive(move(beat.action, at: beat.hitMs + 30))
        guard case let .resolved(result)? = events.first else { Issue.record("expected a result"); return }
        #expect(result.grade == .perfect && result.points >= 150 && engine.streak == 1 && engine.score == result.points)
    }

    @Test func timingGradesWidenWithOffsetAndLateMovesMiss() {
        let window = SparringConfiguration.Difficulty.contender.windowMs
        for (offset, grade) in [(window * 0.2, SparringGrade.perfect), (window * 0.4, .great), (window * 0.9, .good)] {
            var engine = SparringEngine(configuration: .init(difficulty: .contender), seed: 3)
            engine.start(atMs: 0)
            let beat = firstBeat(&engine)
            guard case let .resolved(result)? = engine.receive(move(beat.action, at: beat.hitMs - offset)).first else { Issue.record("no result"); return }
            #expect(result.grade == grade, "offset \(offset)")
        }
        var late = SparringEngine(configuration: .init(difficulty: .contender), seed: 3)
        late.start(atMs: 0)
        let beat = firstBeat(&late)
        let expired = late.update(atMs: beat.hitMs + window + 10)
        #expect(expired.contains { if case let .resolved(r) = $0 { return r.grade == .miss && r.beat.id == beat.id } else { return false } })
    }

    @Test func wrongMoveBreaksTheStreakButOnlyMissedDodgesCostLives() {
        var engine = SparringEngine(configuration: .init(difficulty: .rookie, kinds: [.straight]), seed: 11)
        engine.start(atMs: 0)
        let beat = firstBeat(&engine)
        _ = engine.receive(move(beat.action, at: beat.hitMs))
        #expect(engine.streak == 1)
        let next = firstBeat(&engine, from: beat.hitMs)
        let wrong: FightAction = next.action == .straight(.left) ? .straight(.right) : .straight(.left)
        guard case let .resolved(result)? = engine.receive(move(wrong, at: next.hitMs)).first else { Issue.record("no result"); return }
        #expect(result.grade == .wrong && engine.streak == 0 && engine.lives == SparringConfiguration.Difficulty.rookie.lives)

        var dodging = SparringEngine(configuration: .init(difficulty: .champion, kinds: [.duck]), seed: 5)
        dodging.start(atMs: 0)
        var t = 0.0, knockedOut = false
        while !knockedOut && t < 120_000 { t += 50; knockedOut = dodging.update(atMs: t).contains(.knockedOut) }
        #expect(knockedOut && dodging.lives == 0 && dodging.phase == .finished)
    }

    @Test func multiplierStepsUpEveryEightHitsAndCapsAtFour() {
        var engine = SparringEngine(configuration: .init(difficulty: .rookie, rounds: 1, roundSeconds: 300), seed: 21)
        engine.start(atMs: 0)
        var t = 0.0
        while engine.streak < 30 && t < 300_000 {
            t += 20; _ = engine.update(atMs: t)
            for beat in engine.active where t >= beat.hitMs { _ = engine.receive(move(beat.action, at: beat.hitMs)) }
            if engine.streak == 8 { #expect(engine.multiplier == 2) }
        }
        #expect(engine.streak >= 30 && engine.multiplier == 4)
    }

    @Test func roundsRestAndFinish() {
        var engine = SparringEngine(configuration: .init(difficulty: .rookie, rounds: 2, roundSeconds: 20, restSeconds: 5, kinds: [.straight]), seed: 2)
        engine.start(atMs: 0)
        var t = 0.0, sawRest = false, events: [SparringEngine.Event] = []
        while engine.phase != .finished && t < 200_000 {
            t += 50
            events += engine.update(atMs: t)
            for beat in engine.active where t >= beat.hitMs { _ = engine.receive(move(beat.action, at: beat.hitMs)) }
            if engine.phase == .rest { sawRest = true }
        }
        #expect(sawRest && events.contains(.roundStarted(2)) && events.contains(.finished))
        #expect(engine.summary.roundsCompleted == 2 && engine.summary.accuracy == 1)
    }

    @Test func combinationsUseOnlyEnabledMovesAndAreRealBoxingCombos() {
        var engine = SparringEngine(configuration: .init(difficulty: .champion, roundSeconds: 120, kinds: [.straight, .hook]), seed: 99)
        engine.start(atMs: 0)
        var t = 0.0, seen: Set<FightAction.Kind> = []
        while t < 120_000 { t += 100; for case let .spawned(beat) in engine.update(atMs: t) { seen.insert(beat.action.kind) }; for b in engine.active { _ = engine.receive(move(b.action, at: b.hitMs)) } }
        #expect(seen.isSubset(of: [.straight, .hook]) && seen.contains(.hook))
    }

    @Test func detectionCheckAsksEveryMoveFourTimesAndRecordsWhatWasSeen() {
        var engine = SparringEngine(configuration: .init(mode: .check), seed: 4)
        engine.start(atMs: 0)
        var t = 0.0, asked: [FightAction: Int] = [:]
        while engine.phase != .finished && t < 200_000 {
            t += 50
            for case let .spawned(beat) in engine.update(atMs: t) { asked[beat.action, default: 0] += 1 }
            // Pretend every hook is seen as a jab: the table must show that confusion.
            for beat in engine.active where t >= beat.hitMs {
                let seen: FightAction = beat.action == .hook(.left) ? .straight(.left) : beat.action
                _ = engine.receive(move(seen, at: beat.hitMs))
            }
        }
        #expect(asked.count == 9 && asked.values.allSatisfy { $0 == 4 })
        let hook = engine.summary.moves["Left hook"]
        #expect(hook?.asked == 4 && hook?.hit == 0 && hook?.detectedAs["Jab"] == 4)
        #expect(engine.lives == SparringConfiguration.Difficulty.contender.lives) // no lives in a check
    }
}

struct SparringDrillTests {
    @Test func cameraDrillsRepeatTheirOwnMovesForTheStance() throws {
        let item = ActivityPrescription(id: "a", activityID: "one-two-hook-v1", mode: .camera, sets: 1, reps: 0, workSeconds: 60, restSeconds: 0)
        let orthodox = try #require(item.sparringConfiguration(stance: .orthodox))
        #expect(orthodox.mode == .drill && orthodox.sequence == [.straight(.left), .straight(.right), .hook(.left)])
        let southpaw = try #require(item.sparringConfiguration(stance: .southpaw))
        #expect(southpaw.sequence == [.straight(.right), .straight(.left), .hook(.right)])
        var engine = SparringEngine(configuration: orthodox, seed: 1)
        engine.start(atMs: 0)
        var t = 0.0, seen: [FightAction] = []
        while t < 60_000 { t += 50; for case let .spawned(b) in engine.update(atMs: t) { seen.append(b.action) } }
        #expect(seen.count >= 9 && Array(seen.prefix(6)) == orthodox.sequence! + orthodox.sequence!)
        #expect(engine.lives == orthodox.difficulty.lives) // drills never cost lives
    }

    @Test func padDrillsKeepThePadEngineAndSparringRoundsAreFullMix() throws {
        let pad = ActivityPrescription(id: "a", activityID: "jab-reset-v1", mode: .camera, sets: 1, reps: 0, workSeconds: 60, restSeconds: 0)
        #expect(pad.sparringConfiguration(stance: .orthodox) == nil && pad.cameraConfiguration(stance: .orthodox, suggestedLevel: .beginner) != nil)
        let round = ActivityPrescription(id: "b", activityID: "sparring-round-v1", mode: .camera, sets: 1, reps: 0, workSeconds: 120, restSeconds: 0)
        let config = try #require(round.sparringConfiguration(stance: .orthodox))
        #expect(config.mode == .arcade && config.sequence == nil && config.roundSeconds == 120)
        #expect(round.cameraConfiguration(stance: .orthodox, suggestedLevel: .beginner) == nil)
    }

    @Test func everyCameraDrillExistsInTheCatalogWithACameraMode() {
        for id in SparringDrill.all.keys {
            let activity = ActivityCatalog.find(id)
            #expect(activity?.modes.contains(.camera) == true, "\(id)")
        }
        #expect(ActivityCatalog.find("duck-v1") != nil && ActivityCatalog.find("goblet-squat-v1")?.equipment == ["Dumbbells"])
    }
}
